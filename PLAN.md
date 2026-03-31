# Undertow Implementation Plan

## Decisions Summary

| Decision | Choice |
|----------|--------|
| Architecture | Full companion app + LaunchAgent + Source Editor Extension |
| Deployment target | macOS 26 only |
| MCP SDK | `modelcontextprotocol/swift-sdk` (official) |
| Project management | Tuist for all targets |
| Distribution | Sandboxed host app + non-sandboxed privileged helper, notarized |

## Critical Architecture Constraints Discovered

### 1. SMAppService Sandbox Inheritance (macOS 14.2+)
If the host app is sandboxed, any helper registered via `SMAppService` must also be sandboxed. This conflicts with our need for a non-sandboxed helper with Accessibility API and arbitrary FSEvents access.

**Solution:** Follow the CopilotForXcode pattern — use a **three-layer XPC architecture** with a CommunicationBridge. The sandboxed Source Editor Extension uses `temporary-exception.mach-lookup` entitlements to reach the non-sandboxed bridge, which forwards to the helper via an anonymous `NSXPCListenerEndpoint`. Distribution is direct (DMG/Homebrew), not Mac App Store.

### 2. Three-Layer XPC Architecture (from CopilotForXcode)
A sandboxed extension **cannot** directly query Xcode's AX tree or access the file system. All heavy work must be delegated out-of-process via XPC.

**Solution:** Three-layer design proven in production by CopilotForXcode:
```
UndertowExtension (.appex, sandboxed)
    ↓ NSXPCConnection to mach service
UndertowBridge (non-sandboxed, lightweight forwarder)
    ↓ NSXPCListenerEndpoint forwarding
UndertowHelper (non-sandboxed, background agent — MCP, Flow, Relevance, Memory)
```

### 3. Foundation Models Background Pause
The on-device LLM pauses when the app enters the background. The relevance engine must handle this.

**Solution:** The non-sandboxed helper runs as a foreground process (accessory app with `NSApp.setActivationPolicy(.accessory)`, like CopilotForXcode's ExtensionService). For cases where the model isn't available, fall back to BM25 text search + IndexStoreDB structural queries.

### 4. Foundation Models 4,096 Token Context Limit
`LanguageModelSession` has a 4,096-token combined limit for instructions, prompts, and responses.

**Solution:** Use small, focused prompts per code chunk for relevance scoring. Fan out with `TaskGroup` concurrency. Keep chunk sizes under ~2K tokens to leave room for instructions and response.

### 5. XPC Connection Resilience (from CopilotForXcode)
XPC connections can be invalidated at any time (process crash, sleep/wake, etc.).

**Solution:** Adopt CopilotForXcode's patterns:
- **`@globalActor XPCServiceActor`** — dedicated actor for thread-safe XPC access
- **Lazy auto-reconnect** — rebuild connection on invalidation via lazy property
- **60-second ping** — helper pings bridge periodically to stay alive and detect disconnection
- **`AutoFinishContinuation`** — bridge callback-based `NSXPCConnection` APIs to async/await

### 6. Xcode AX Observation (from CopilotForXcode)
Polling the AX tree is wasteful. CopilotForXcode uses `AXObserver` with `AsyncSequence` streaming instead.

**Solution:** Use `AXNotificationStream` pattern (not polling):
- Subscribe to `kAXSelectedTextChangedNotification`, `kAXValueChangedNotification`, `kAXFocusedUIElementChangedNotification`
- Stream via `AsyncSequence` with proper `AXObserverCreateWithInfoCallback`
- Set `AXUIElement.setGlobalMessagingTimeout(3)` to prevent hangs
- Wrap in `@globalActor XcodeInspectorActor` for thread safety

---

## Target Architecture (Tuist)

```
Project.swift defines 6 targets:
├── Undertow              (macOS app, sandboxed, SwiftUI host — settings & management UI)
├── UndertowBridge        (command-line tool, non-sandboxed, lightweight XPC forwarder)
├── UndertowHelper        (command-line tool, non-sandboxed, background agent — MCP, Flow, AI)
├── UndertowExtension     (Xcode Source Editor Extension, .appex, sandboxed)
├── UndertowKit           (framework, shared XPC protocols + models between all targets)
└── UndertowTests         (unit tests)
```

**Bundle layout:**
```
Undertow.app/
├── Contents/
│   ├── MacOS/Undertow
│   ├── PlugIns/UndertowExtension.appex
│   ├── Resources/UndertowBridge
│   ├── Resources/UndertowHelper
│   ├── Library/LaunchAgents/dev.21.Undertow.Bridge.plist
│   ├── Library/LaunchAgents/dev.21.Undertow.Helper.plist
│   └── Frameworks/UndertowKit.framework
```

**Entitlements matrix:**

| Target | Sandboxed | Key Entitlements |
|--------|-----------|------------------|
| Undertow | Yes | `com.apple.security.app-sandbox`, `com.apple.security.application-groups: group.dev.21.Undertow`, `com.apple.security.temporary-exception.mach-lookup.global-name: [dev.21.Undertow.Bridge, dev.21.Undertow.Helper]` |
| UndertowBridge | No | `com.apple.security.application-groups: group.dev.21.Undertow`, `com.apple.security.cs.disable-library-validation` |
| UndertowHelper | No | `com.apple.security.application-groups: group.dev.21.Undertow`, `com.apple.security.cs.disable-library-validation` |
| UndertowExtension | Yes (auto) | `com.apple.security.app-sandbox`, `com.apple.security.application-groups: group.dev.21.Undertow`, `com.apple.security.temporary-exception.mach-lookup.global-name: [dev.21.Undertow.Bridge]` |

---

## Phase 0: Foundation & Scaffolding

### 0.1 — Update Project.swift for Multi-Target Architecture

**Files to modify:**
- `Project.swift` — Add all 6 targets with dependencies and embedding rules
- `Package.swift` — Add dependencies: `modelcontextprotocol/swift-sdk`, `swiftlang/swift-syntax`

**New targets in `Project.swift`:**

1. **UndertowKit** (framework)
   - Product: `.framework`
   - Sources: `Sources/UndertowKit/**`
   - Contains: XPC protocol definitions (`@objc` protocols), shared models, XPC constants, `AutoFinishContinuation` helper
   - Dependencies: `swift-syntax`, `mcp-swift-sdk`

2. **UndertowBridge** (command-line tool) — *new, from CopilotForXcode pattern*
   - Product: `.commandLineTool`
   - Sources: `Sources/UndertowBridge/**`
   - No sandbox entitlements (non-sandboxed)
   - Entitlements: App Group, `cs.disable-library-validation`
   - Dependencies: `UndertowKit`
   - Role: Lightweight mach service forwarder — registers `dev.21.Undertow.Bridge`, forwards XPC calls to helper via `NSXPCListenerEndpoint`
   - Reference: CopilotForXcode's `CommunicationBridge/` (~100 lines total)

3. **UndertowHelper** (command-line tool)
   - Product: `.commandLineTool`
   - Sources: `Sources/UndertowHelper/**`
   - No sandbox entitlements (non-sandboxed)
   - Entitlements: App Group, `cs.disable-library-validation`
   - Dependencies: `UndertowKit`
   - Role: Core agent — MCP server, flow engine, relevance engine, memory store
   - Runs as accessory app (`NSApp.setActivationPolicy(.accessory)`) like CopilotForXcode's ExtensionService
   - Creates anonymous `NSXPCListener`, sends endpoint to bridge

4. **UndertowExtension** (app extension)
   - Product: `.appExtension`
   - Sources: `Sources/UndertowExtension/**`
   - Info.plist: `NSExtensionPointIdentifier = com.apple.dt.Xcode.extension.source-editor`, `XCSourceEditorExtensionPrincipalClass = UndertowExtension.SourceEditorExtension`
   - Entitlements: sandbox + App Group + mach-lookup exception for bridge
   - Dependencies: `UndertowKit`
   - Role: Lightweight command registration, forwards to bridge via XPC (like CopilotForXcode's EditorExtension)

5. **Undertow** (main app) — modify existing
   - Add dependencies: `UndertowKit`
   - Embed: `UndertowBridge` (in Resources), `UndertowHelper` (in Resources), `UndertowExtension` (in PlugIns)
   - Copy: LaunchAgent plists (in Library/LaunchAgents)
   - Entitlements: sandbox + App Group + mach-lookup exceptions for bridge and helper
   - Keep sandbox enabled

6. **UndertowTests** — modify existing
   - Add dependency: `UndertowKit`

### 0.2 — Create Shared XPC Infrastructure in UndertowKit

**New files:**
- `Sources/UndertowKit/XPC/XPCConstants.swift` — Service names, App Group ID:
  ```swift
  public enum UndertowXPC {
      public static let appGroup = "group.dev.21.Undertow"
      public static let bridgeServiceName = "dev.21.Undertow.Bridge"
      public static let helperServiceName = "dev.21.Undertow.Helper"
  }
  ```
- `Sources/UndertowKit/XPC/BridgeXPCProtocol.swift` — Bridge protocol (from CopilotForXcode pattern):
  ```swift
  @objc public protocol BridgeXPCProtocol {
      func launchHelperIfNeeded(withReply reply: @escaping (NSXPCListenerEndpoint?) -> Void)
      func updateHelperEndpoint(_ endpoint: NSXPCListenerEndpoint, withReply reply: @escaping () -> Void)
      func ping(withReply reply: @escaping () -> Void)
  }
  ```
- `Sources/UndertowKit/XPC/HelperXPCProtocol.swift` — Helper protocol:
  ```swift
  @objc public protocol HelperXPCProtocol {
      func getFlowContext(withReply reply: @escaping (Data?, Error?) -> Void)
      func semanticSearch(query: Data, withReply reply: @escaping (Data?, Error?) -> Void)
      func getMemories(query: Data, withReply reply: @escaping (Data?, Error?) -> Void)
      func saveMemory(content: Data, withReply reply: @escaping (Error?) -> Void)
      func createCheckpoint(name: String, withReply reply: @escaping (Error?) -> Void)
      func listCheckpoints(withReply reply: @escaping (Data?, Error?) -> Void)
      func revertToCheckpoint(name: String, withReply reply: @escaping (Error?) -> Void)
      func ping(withReply reply: @escaping () -> Void)
  }
  ```
- `Sources/UndertowKit/XPC/XPCServiceActor.swift` — Global actor for thread-safe XPC access:
  ```swift
  @globalActor public enum XPCServiceActor: GlobalActor {
      public actor ActorType {}
      public static let shared = ActorType()
  }
  ```
- `Sources/UndertowKit/XPC/AutoFinishContinuation.swift` — Bridge XPC callbacks to async/await (from CopilotForXcode)
- `Sources/UndertowKit/Models/FlowContext.swift` — `FlowContext` struct (Codable)
- `Sources/UndertowKit/Models/Memory.swift` — `Memory` struct (Codable)
- `Sources/UndertowKit/Models/CodeChunk.swift` — `CodeChunk` struct (Codable)

### 0.3 — Scaffold the Bridge

**New files:**
- `Sources/UndertowBridge/main.swift` — Entry point:
  ```swift
  // Register mach service listener for bridge
  let listener = NSXPCListener(machServiceName: UndertowXPC.bridgeServiceName)
  listener.delegate = ServiceDelegate()
  listener.resume()
  RunLoop.main.run()
  ```
- `Sources/UndertowBridge/ServiceDelegate.swift` — Accepts XPC connections, implements `BridgeXPCProtocol`:
  - Stores the helper's `NSXPCListenerEndpoint`
  - On `launchHelperIfNeeded`: returns endpoint or launches helper from app bundle
  - Reference: CopilotForXcode's `CommunicationBridge/ServiceDelegate.swift` (~80 lines)

### 0.4 — Scaffold the Helper

**New files:**
- `Sources/UndertowHelper/main.swift` — Entry point:
  ```swift
  // Run as accessory app (invisible, no dock icon)
  NSApp.setActivationPolicy(.accessory)
  // Create anonymous XPC listener
  let xpcListener = NSXPCListener.anonymous()
  // Register endpoint with bridge
  // Start MCP server on stdio
  // Start 60-second ping task to bridge
  ```
- `Sources/UndertowHelper/XPC/XPCController.swift` — Manages XPC listener + bridge connection:
  - Creates anonymous listener, sends endpoint to bridge via `updateHelperEndpoint`
  - 60-second ping task to keep alive (from CopilotForXcode pattern)
  - Auto-reconnect on invalidation
- `Sources/UndertowHelper/MCPServer.swift` — MCP server using `modelcontextprotocol/swift-sdk` with stdio transport
- `Sources/UndertowHelper/Tools/HelloTool.swift` — Trivial hello-world MCP tool for validation

**Validation:** After `tuist generate`, build and run the helper standalone. Verify it responds to MCP `tools/list` and `tools/call` via stdio.

### 0.5 — Register MCP Server with Xcode's Claude Agent

**Action:** Programmatically write (or instruct user to add) the helper's MCP config to `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude.json` under the project's `mcpServers` key:

```json
"undertow": {
  "command": "/path/to/Undertow.app/Contents/Resources/UndertowHelper",
  "args": ["--mcp"],
  "env": {}
}
```

**Validation:** Open Xcode, start a Claude Agent session, run `/context` — verify "undertow" appears with the hello tool.

### 0.6 — Scaffold Hook System

**New files:**
- `Sources/UndertowHelper/Hooks/UserPromptSubmitHook.swift` — Reads flow context, returns `additionalContext`

**Action:** Register the hook in `.claude.json`:
```json
"hooks": {
  "UserPromptSubmit": [{"command": "/path/to/UndertowHelper --hook user-prompt-submit"}]
}
```

**Validation:** Submit a prompt in Xcode's Claude Agent. Verify the hook fires (log to a file).

### 0.7 — Scaffold Source Editor Extension (Minimal)

**New files:**
- `Sources/UndertowExtension/SourceEditorExtension.swift` — `NSObject, XCSourceEditorExtension`:
  ```swift
  class SourceEditorExtension: NSObject, XCSourceEditorExtension {
      var commandDefinitions: [[XCSourceEditorCommandDefinitionKey: Any]] {
          // Register commands dynamically (like CopilotForXcode)
      }
  }
  ```
- `Sources/UndertowExtension/Commands/PingCommand.swift` — Trivial command that connects to bridge via XPC and returns success

**Validation:** Build, enable extension in System Settings > Extensions > Xcode Source Editor, verify command appears in Xcode's Editor menu.

### 0.8 — Host App Launches Bridge + Helper

**Modify:** `Sources/Undertow/UndertowApp.swift`
- On launch, launch bridge from `Bundle.main.url(forResource: "UndertowBridge")`
- Bridge auto-launches helper (or host app launches helper directly as fallback)
- Add menu bar status item showing service status (bridge up, helper up, AX permission)
- Check Accessibility permission via `AXIsProcessTrusted()` and prompt if needed

**New files:**
- `Sources/Undertow/Services/XPCClient.swift` — Client wrapper using `@XPCServiceActor`, auto-reconnect, lazy connection (from CopilotForXcode's `XPCExtensionService` pattern)

**Deliverable:** Skeleton 6-target app that builds. Bridge and helper run as background processes. Helper serves MCP tools visible in Xcode's `/context`. Hook fires on prompt submit. XPC communication works across all layers. Extension appears in Xcode's Editor menu.

---

## Phase 1: Flow Engine — Real-Time Action Awareness

### 1.1 — File System Observer

**New files:**
- `Sources/UndertowHelper/Flow/FileSystemObserver.swift`

**Implementation:**
- Use `DispatchSource.makeFileSystemObjectSource` or `FSEvents` API to watch project directory
- Track: creates, modifications, deletes, renames
- Maintain rolling buffer: last 50 events or last 10 minutes (whichever is smaller)
- Events stored as `[FileEvent]` in memory, each with path, type, timestamp
- Debounce rapid changes (e.g., save + backup = 1 event)

### 1.2 — Build Log Observer

**New files:**
- `Sources/UndertowHelper/Flow/BuildLogObserver.swift`

**Implementation:**
- Watch `DerivedData/<project>/Logs/Build/` for new `.xcactivitylog` files
- Parse compressed build logs for: success/failure, error messages, warning counts
- Alternatively, query Xcode's MCP `GetBuildLog` tool if available from the helper
- Store latest build result as `BuildStatus` struct

### 1.3 — Xcode State Observer (Accessibility API)

**New files:**
- `Sources/UndertowHelper/Flow/XcodeObserver.swift`
- `Sources/UndertowHelper/Flow/AXNotificationStream.swift` — `AsyncSequence` wrapper for AX events
- `Sources/UndertowHelper/Flow/AXExtensions.swift` — `AXUIElement` convenience extensions

**Implementation (from CopilotForXcode's XcodeInspector pattern):**
- Wrap in `@globalActor XcodeInspectorActor` for thread-safe AX access
- Use `AXObserverCreateWithInfoCallback` + `AsyncSequence` streaming (**not polling**):
  - Subscribe to: `kAXSelectedTextChangedNotification`, `kAXValueChangedNotification`, `kAXFocusedUIElementChangedNotification`, `kAXMainWindowChangedNotification`
  - Stream events via `AsyncPassthroughSubject` pattern
- Set `AXUIElement.setGlobalMessagingTimeout(3)` to prevent hangs
- Track via `NSRunningApplication` + `AXUIElement.fromRunningApplication()`:
  - Active file path (from document attribute on focused window)
  - Cursor position (from `kAXSelectedTextRangeAttribute` on source editor element)
  - Active scheme/simulator (from toolbar children)
  - Workspace URL (from window document path)
- Detect Xcode activation/deactivation via `NSWorkspace.shared.notificationCenter`
- Reference: `CopilotForXcode/Tool/Sources/XcodeInspector/`, `AXExtension/`, `AXNotificationStream/`

### 1.4 — Flow Context Aggregator

**New files:**
- `Sources/UndertowHelper/Flow/FlowContextAggregator.swift`

**Implementation:**
- Combine all three observer streams into `FlowContext` struct
- Compress intelligently: group consecutive edits to same file, summarize navigation patterns
- Example output: "Developer has been editing `NetworkService.swift` for 5 minutes, focusing on `fetchData()`. Last build failed with 2 errors in `APIClient.swift`. Recently visited: `Models/User.swift`, `Tests/NetworkTests.swift`."
- Write to `.undertow/flow-context.json` in project root (or cache directory)
- Expose as MCP tool: `get_flow_context`

### 1.5 — Wire Up UserPromptSubmit Hook

**Modify:** `Sources/UndertowHelper/Hooks/UserPromptSubmitHook.swift`

**Implementation:**
- On hook invocation, read current `FlowContext` from the aggregator
- Format as concise, structured text
- Return as `additionalContext` in hook response JSON
- Include: current file, recent edits, build status, navigation history

**Deliverable:** Every prompt to Xcode's Claude Agent automatically includes awareness of what the developer is doing — file edits, build state, navigation history, and Xcode-specific state.

---

## Phase 2: Semantic Relevance Engine

### 2.1 — Code Chunker (SwiftSyntax)

**New files:**
- `Sources/UndertowKit/Indexing/CodeChunker.swift`
- `Sources/UndertowKit/Indexing/SwiftChunkVisitor.swift`

**Implementation:**
- Parse `.swift` files using SwiftSyntax's `Parser.parse(source:)`
- Implement `SyntaxVisitor` subclass that extracts chunks at function/type/extension level
- Each `CodeChunk`: file path, line range, signature, doc comments, containing type, raw source
- Re-chunk on file change events from Flow Engine (debounced)
- For non-Swift files: fall back to line-based chunking (50-line windows with 10-line overlap)

### 2.2 — IndexStoreDB Integration

**New files:**
- `Sources/UndertowHelper/Indexing/IndexStoreService.swift`

**Implementation:**
- Add `swiftlang/indexstore-db` as a dependency
- Load project index from `DerivedData/<project>/Index.noindex/DataStore/`
- Expose symbol-level queries:
  - `findSymbolReferences(symbol:)` — all call sites of a function/type
  - `findConformances(protocol:)` — all types conforming to a protocol
  - `findCallers(function:)` — direct callers of a function
- Expose as MCP tools: `find_symbol_references`, `find_conformances`

### 2.3 — On-Device Relevance Scorer (Foundation Models)

**New files:**
- `Sources/UndertowHelper/Relevance/RelevanceScorer.swift`
- `Sources/UndertowKit/Models/ChunkRelevance.swift`

**Implementation:**
- Define `@Generable` struct for scoring:
  ```swift
  @Generable struct ChunkRelevance {
      @Guide(.range(0...10)) var score: Int
      @Guide(description: "Why this chunk matters") var reason: String
  }
  ```
- For each query, create a `TaskGroup` that fans out `LanguageModelSession` calls
- BM25 pre-filter: narrow to top 50 candidates by text search first
- Then LLM-score the top 50, return top 5-10 with reasons
- Cache scores per `(queryHash, chunkHash)` pair
- Graceful fallback: if Foundation Models unavailable, return BM25-only results

### 2.4 — Hybrid Retrieval MCP Tool

**New files:**
- `Sources/UndertowHelper/Tools/SemanticSearchTool.swift`

**Implementation:**
- MCP tool: `semantic_search(query: String)` → ranked `[CodeChunk]` with reasons
- Strategy:
  - Structural queries (contains symbol names) → IndexStoreDB
  - Semantic queries (natural language) → Foundation Models scorer
  - Mixed → combine both, deduplicate by file+lineRange, re-rank
- Include source of each result (index vs. semantic) for transparency

### 2.5 — Performance: Importance Map

**New files:**
- `Sources/UndertowHelper/Relevance/ImportanceMap.swift`

**Implementation:**
- Pre-compute file importance scores based on:
  - Recent edit frequency (from Flow Engine)
  - Git churn (commits touching the file in last 30 days)
  - Dependency depth (files imported by many others score higher)
- Use importance map to weight BM25 pre-filter results
- Refresh on project open and periodically (every 5 minutes)

**Deliverable:** Natural language codebase search that combines compiler-accurate symbol resolution with on-device LLM scoring, exposed as an MCP tool.

---

## Phase 3: Persistent Memory System

### 3.1 — Memory Store

**New files:**
- `Sources/UndertowHelper/Memory/MemoryStore.swift`
- `Sources/UndertowKit/Models/Memory.swift` (already scaffolded in Phase 0)

**Implementation:**
- Store memories as JSON: `.undertow/memories.json` in project root
- Each memory: `{ id: UUID, content: String, source: "user"|"auto", timestamp: Date, tags: [String] }`
- CRUD operations: create, read, update, delete
- Expose as MCP tools: `get_memories(query:)`, `save_memory(content:tags:)`

### 3.2 — Memory Relevance Retrieval

**Modify:** `Sources/UndertowHelper/Memory/MemoryStore.swift`

**Implementation:**
- On `get_memories(query:)`, score existing memories against the query using Foundation Models
- Same `@Generable` scoring pattern as code chunks but simpler (memories are short text)
- Always inject user-created memories unconditionally (these are project rules)
- Auto-generated memories are scored and only top-k injected

### 3.3 — Auto-Memory Detection

**New files:**
- `Sources/UndertowHelper/Hooks/PostToolUseHook.swift`

**Implementation:**
- PostToolUse hook: after agent interactions, detect memory candidates
- Use Foundation Models: "Based on this interaction, extract a reusable fact or convention"
- Send candidate to host app via XPC for user approval (notification)
- On approval, save to memory store
- Examples: "This project uses async/await exclusively", "API layer uses repository pattern"

### 3.4 — Wire Up to UserPromptSubmit Hook

**Modify:** `Sources/UndertowHelper/Hooks/UserPromptSubmitHook.swift`

**Implementation:**
- On each prompt, score memories against the current flow context + prompt
- Inject top-k relevant memories + all user rules as `additionalContext`
- Format: separate section labeled "Project Memories" in the context

### 3.5 — Memory Management UI

**New files:**
- `Sources/Undertow/Views/MemoryListView.swift`
- `Sources/Undertow/Views/MemoryEditorView.swift`

**Implementation:**
- SwiftUI list: display all memories, filter by tag
- Create/edit/delete memories
- Toggle auto-generated vs user-created
- Tag management (architecture, conventions, dependencies, testing)
- Import/export as JSON for team sharing

### 3.6 — CLAUDE.md Sync

**New files:**
- `Sources/UndertowHelper/Memory/ClaudeMDSync.swift`

**Implementation:**
- Optionally write user-created memories to project's `CLAUDE.md`
- Parse existing `CLAUDE.md` on load, import as memories
- Bidirectional sync with conflict detection (timestamp-based)

**Deliverable:** Persistent cross-session memory that auto-generates from interactions, scores by relevance, and syncs with CLAUDE.md.

---

## Phase 4: Checkpoints & Reverts

### 4.1 — Auto-Checkpoint via PreToolUse Hook

**New files:**
- `Sources/UndertowHelper/Hooks/PreToolUseHook.swift`
- `Sources/UndertowHelper/Checkpoints/CheckpointManager.swift`

**Implementation:**
- PreToolUse hook: before any Write/Edit tool call, create a git commit
- Use shadow branch: `undertow/checkpoints`
- Commit message: `[undertow] {timestamp} — {agent intent summary}`
- Use `Process` to shell out to `git` (simpler than libgit2 dependency)
- Keep checkpoint branch separate from working branch

### 4.2 — Named Checkpoints MCP Tool

**New files:**
- `Sources/UndertowHelper/Tools/CheckpointTools.swift`

**Implementation:**
- `create_checkpoint(name:)` — creates a git tag `undertow-cp/{name}` on current state
- `list_checkpoints()` — lists all checkpoint tags with timestamps and diffs
- `revert_to_checkpoint(name:)` — creates pre-revert checkpoint, then hard resets working tree

### 4.3 — Checkpoint Browser UI

**New files:**
- `Sources/Undertow/Views/CheckpointListView.swift`
- `Sources/Undertow/Views/CheckpointDiffView.swift`

**Implementation:**
- List all checkpoints with creation time and summary
- Show diff from current state to any checkpoint
- One-click revert button with confirmation dialog
- Filter by date range or search by name

**Deliverable:** Git-backed project snapshots with named checkpoints, auto-created before every agent file modification.

---

## Phase 5: Auto-Lint and Build Loop

### 5.1 — PostToolUse Hook: Auto-Lint

**Modify:** `Sources/UndertowHelper/Hooks/PostToolUseHook.swift`

**Implementation:**
- After Write/Edit tool calls, run `swiftlint` on changed files
- If auto-fixable violations: run `swiftlint --fix`, report what was fixed
- If non-fixable violations: inject as `additionalContext` for the next turn
- Only lint Swift files; skip non-Swift

### 5.2 — PostToolUse Async Hook: Auto-Build

**Modify:** `Sources/UndertowHelper/Hooks/PostToolUseHook.swift`

**Implementation:**
- After file edits, trigger a background build via Xcode's MCP `BuildProject` tool (or `xcodebuild` CLI)
- Return `async: true` from the hook so it doesn't block the agent
- When build completes, inject results (success/errors) as context for the next turn
- Parse build errors into structured format: file, line, message

### 5.3 — Test Runner MCP Tool

**New files:**
- `Sources/UndertowHelper/Tools/TestRunnerTool.swift`

**Implementation:**
- MCP tool: `run_tests(target:filter:)` — runs tests via `xcodebuild test` or Xcode MCP
- Parse test results: pass/fail counts, failure messages with file/line
- Optional: auto-run tests for changed files after edits (configurable)

**Deliverable:** Automatic lint fixing and build-error feedback loop that closes the edit-build-fix cycle without developer intervention.

---

## Phase 6: Inline Completions & Command Mode (Optional)

### 6.1 — Source Editor Extension: Command Mode

**Modify:** `Sources/UndertowExtension/`

**Implementation (from CopilotForXcode's EditorExtension pattern):**
- Commands are lightweight — extract `EditorContent` from `XCSourceEditorCommandInvocation.buffer`, immediately forward to bridge/helper via XPC
- Extract editor state: `buffer.completeBuffer`, `buffer.lines`, `buffer.contentUTI`, cursor from `buffer.selections`, `buffer.tabWidth`
- Apply results via `invocation.buffer.lines.apply(modifications)` + selection restoration
- Use timeout pattern: `Task(priority: nil, timeout: 10) { ... }` to avoid hanging Xcode

**Commands to register:**
- `InlineEditCommand` — `⌘+I`: capture selection + surrounding context, send to helper → Claude API or Foundation Models → apply replacement
- `ExplainCommand` — Explain selected code
- `RefactorCommand` — Refactor selected code
- `AddTestsCommand` — Generate tests for selected code

**Command definition pattern (from CopilotForXcode):**
```swift
protocol CommandType: AnyObject {
    var commandClassName: String { get }
    var identifier: String { get }
    var name: String { get }
}
```

### 6.2 — Inline Completion Overlay (Advanced)

**New files:**
- `Sources/UndertowHelper/Inline/CompletionOverlay.swift`
- `Sources/UndertowHelper/Inline/SuggestionWidget.swift`

**Implementation (from CopilotForXcode's SuggestionWidget pattern):**
- Use Accessibility API to position an overlay window at the cursor location in Xcode's editor
- Source completions from Foundation Models (fast, on-device) for simple cases
- Tab to accept (via Source Editor Extension command `AcceptSuggestion`), Esc to dismiss
- Feed Flow Engine context into completion prompts for awareness
- Use `RealtimeSuggestionController` pattern: throttle to 200ms windows, debounce rapid typing

**Deliverable:** Inline completions and `⌘+I` command mode in Xcode's editor.

---

## Dependency Summary

| Package | Purpose | Target |
|---------|---------|--------|
| `modelcontextprotocol/swift-sdk` | MCP server implementation | UndertowKit |
| `swiftlang/swift-syntax` | Code chunking, AST parsing | UndertowKit |
| `swiftlang/indexstore-db` | Compiler-level symbol index | UndertowHelper |
| `21-DOT-DEV/swift-plugin-tuist` | Project generation | Package plugin |

---

## File Structure After All Phases

```
Sources/
├── Undertow/                        # Host app (sandboxed)
│   ├── UndertowApp.swift
│   ├── ContentView.swift
│   ├── Services/
│   │   └── XPCClient.swift          # @XPCServiceActor, auto-reconnect, lazy connection
│   └── Views/
│       ├── MemoryListView.swift
│       ├── MemoryEditorView.swift
│       ├── CheckpointListView.swift
│       └── CheckpointDiffView.swift
├── UndertowBridge/                  # Communication bridge (non-sandboxed)
│   ├── main.swift                   # NSXPCListener(machServiceName:), RunLoop.main.run()
│   └── ServiceDelegate.swift        # BridgeXPCProtocol impl, endpoint forwarding
├── UndertowHelper/                  # Background agent (non-sandboxed)
│   ├── main.swift                   # NSApp.setActivationPolicy(.accessory)
│   ├── MCPServer.swift
│   ├── XPC/
│   │   └── XPCController.swift      # Anonymous listener, bridge ping, auto-reconnect
│   ├── Flow/
│   │   ├── FileSystemObserver.swift
│   │   ├── BuildLogObserver.swift
│   │   ├── XcodeObserver.swift      # @XcodeInspectorActor, AX notification streaming
│   │   ├── AXNotificationStream.swift  # AsyncSequence over AXObserver events
│   │   ├── AXExtensions.swift       # AXUIElement convenience (value, title, children, etc.)
│   │   └── FlowContextAggregator.swift
│   ├── Indexing/
│   │   └── IndexStoreService.swift
│   ├── Relevance/
│   │   ├── RelevanceScorer.swift
│   │   └── ImportanceMap.swift
│   ├── Memory/
│   │   ├── MemoryStore.swift
│   │   └── ClaudeMDSync.swift
│   ├── Checkpoints/
│   │   └── CheckpointManager.swift
│   ├── Hooks/
│   │   ├── UserPromptSubmitHook.swift
│   │   ├── PreToolUseHook.swift
│   │   └── PostToolUseHook.swift
│   ├── Tools/
│   │   ├── HelloTool.swift
│   │   ├── SemanticSearchTool.swift
│   │   ├── CheckpointTools.swift
│   │   └── TestRunnerTool.swift
│   └── Inline/
│       ├── CompletionOverlay.swift
│       └── SuggestionWidget.swift
├── UndertowExtension/               # Source Editor Extension (sandboxed)
│   ├── SourceEditorExtension.swift   # XCSourceEditorExtension, dynamic command defs
│   ├── Helpers.swift                 # EditorContent extraction, buffer mutation
│   └── Commands/
│       ├── InlineEditCommand.swift
│       ├── ExplainCommand.swift
│       ├── RefactorCommand.swift
│       └── AddTestsCommand.swift
├── UndertowKit/                     # Shared framework (all targets depend on this)
│   ├── Models/
│   │   ├── FlowContext.swift
│   │   ├── Memory.swift
│   │   ├── CodeChunk.swift
│   │   ├── ChunkRelevance.swift
│   │   └── EditorContent.swift      # Shared editor state model
│   ├── XPC/
│   │   ├── BridgeXPCProtocol.swift   # @objc protocol for bridge
│   │   ├── HelperXPCProtocol.swift   # @objc protocol for helper
│   │   ├── XPCConstants.swift        # Service names, App Group ID
│   │   ├── XPCServiceActor.swift     # @globalActor for thread-safe XPC
│   │   └── AutoFinishContinuation.swift  # Callback → async/await bridge
│   └── Indexing/
│       ├── CodeChunker.swift
│       └── SwiftChunkVisitor.swift
├── UndertowTests/
│   └── UndertowTests.swift
└── Resources/
    ├── UndertowBridge/
    │   └── UndertowBridge.entitlements
    ├── UndertowHelper/
    │   └── UndertowHelper.entitlements
    └── UndertowExtension/
        └── UndertowExtension.entitlements
```

---

## Phase Execution Order

```
Phase 0 (Week 1-2)   ████████░░░░░░░░░░░░░░░░░░  Foundation (6 targets, XPC, MCP, hooks)
Phase 1 (Week 2-4)   ░░░░████████████░░░░░░░░░░  Flow Engine (FSEvents, AX streaming, build)
Phase 2 (Week 4-7)   ░░░░░░░░░░░░████████████░░  Relevance Engine (SwiftSyntax, IndexStore, FM)
Phase 3 (Week 7-9)   ░░░░░░░░░░░░████████████░░  Memory (parallel with Phase 2)
Phase 4 (Week 9-10)  ░░░░░░░░░░░░░░░░░░░░████░░  Checkpoints (git-backed)
Phase 5 (Week 10-11) ░░░░░░░░░░░░░░░░░░░░░░████  Auto-Lint/Build
Phase 6 (Week 11-13) ░░░░░░░░░░░░░░░░░░░░░░░░██  Inline (optional)
```

Phases 2 and 3 can run in parallel — they share `UndertowKit` models but have no code-level dependencies on each other.

---

## Reference Codebases

Key files to cross-reference during implementation:

**CopilotForXcode** (`/Users/csjones/Developer/CopilotForXcode/`):
- `CommunicationBridge/main.swift` + `ServiceDelegate.swift` — Bridge pattern (~100 lines, direct reference for UndertowBridge)
- `ExtensionService/AppDelegate.swift` + `XPCController.swift` — Helper lifecycle (anonymous listener, ping, accessory app)
- `Tool/Sources/XPCShared/XPCServiceProtocol.swift` — XPC protocol design (70+ methods, `@objc`, Data-based serialization)
- `Tool/Sources/XPCShared/XPCExtensionService.swift` — Client wrapper (auto-reconnect, lazy connection, `@XPCServiceActor`)
- `Tool/Sources/XPCShared/XPCCommunicationBridge.swift` — Bridge client (~98 lines)
- `Tool/Sources/XcodeInspector/XcodeInspector.swift` — AX observation (`@globalActor`, `@Published`, `NSRunningApplication`)
- `Tool/Sources/AXNotificationStream/AXNotificationStream.swift` — AsyncSequence over AXObserver
- `Tool/Sources/AXExtension/AXUIElement.swift` — AX convenience extensions (200+ lines)
- `EditorExtension/SourceEditorExtension.swift` — Dynamic command registration
- `EditorExtension/Helpers.swift` — Buffer mutation, EditorContent extraction
- `launchAgent.plist` + `bridgeLaunchAgent.plist` — LaunchAgent configuration
- Entitlements files in each target directory — Exact entitlement patterns

**XcodeCopilot** (`/Users/csjones/Developer/XcodeCopilot/`):
- `Tool/Sources/FocusedCodeFinder/` — SwiftSyntax-based code context extraction (reference for Phase 2 chunker)
- `Tool/Sources/ASTParser/` — TreeSitter-based AST parsing (alternative to SwiftSyntax)
- `Core/Sources/Service/Service.swift` — Plugin architecture and workspace management

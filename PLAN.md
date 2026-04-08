# Undertow Implementation Plan

## Decisions Summary

| Decision | Choice |
|----------|--------|
| Architecture | MCP server (primary) + companion app + optional Source Editor Extension |
| Deployment target | macOS 26 only |
| MCP SDK | `modelcontextprotocol/swift-sdk` (official) |
| Project management | Tuist (`swift-plugin-tuist` v4.169.1) |
| Distribution | App Store, sandboxed with security-scoped bookmarks |
| Process API | `Subprocess` (`swift-subprocess` 0.2.1) — never `Foundation.Process` |
| Flow context delivery | Hybrid: git snapshot (always) + background observer data (when available) |
| Instructional layer | CLAUDE.md (now) + placeholder SKILL.md, defer Commands |

## Critical Discoveries

### 1. Xcode Coding Assistant Does NOT Support Custom Hooks
Confirmed via `/context` command — Xcode shows MCP tools but zero hooks. The `UserPromptSubmit` hook system is specific to Claude Code CLI and is not available in Xcode's Coding Assistant. The "Callback hook success: Success" system reminder is Xcode's own internal hook, not ours.

**Impact:** All hook-based context injection (Phase 0.6, 1.5, 3.3, 3.4, 4.1, 5.1, 5.2 in the original plan) must be redesigned around MCP tools + CLAUDE.md instructions.

### 2. Four Integration Channels in Xcode's Coding Assistant
1. **MCP Server** — Tools and resources (working, primary channel)
2. **CLAUDE.md** — Project instructions loaded into every session (working)
3. **Skills (SKILL.md)** — Registered capabilities (placeholder, future)
4. **Commands** — User-invoked actions (deferred)

### 3. Pull-Based Architecture Replaces Push-Based Hooks
Instead of hooks pushing context into every prompt, CLAUDE.md instructs the agent to call `get_flow_context` at session start. This is a pull model — the agent requests context when needed via MCP tools.

### 4. XPC/Bridge Layer May Be Unnecessary
The three-layer XPC architecture (Extension → Bridge → Helper) is only needed if we use the Source Editor Extension. For the MCP-only path, UndertowHelper runs standalone as a CLI tool. Decision on whether to strip XPC/Bridge is pending — contingent on whether the Source Editor Extension adds enough value.

- AX Observer does NOT need XPC — runs directly in UndertowHelper
- Only the Source Editor Extension requires the XPC Bridge

### 5. Paths with Spaces Break Shell Execution
`/bin/sh -c` splits paths at spaces. The binary installed to `~/Library/Application Support/Undertow/bin/` is symlinked from `~/.undertow/bin/UndertowHelper` (no spaces) for reliable shell invocation.

---

## Current Target Architecture (Tuist)

```
Project.swift defines 6 targets:
├── Undertow              (macOS app, sandboxed, SwiftUI host — settings & management UI)
├── UndertowBridge        (command-line tool, non-sandboxed, XPC forwarder — may be stripped)
├── UndertowHelper        (command-line tool, non-sandboxed, MCP server + flow engine)
├── UndertowExtension     (Xcode Source Editor Extension, .appex — may be stripped)
├── UndertowKit           (static library, shared models + ConfigManager + BookmarkManager)
└── UndertowTests         (unit + integration tests, 75 passing)
```

**Binary deployment:**
```
~/Library/Application Support/Undertow/bin/UndertowHelper  (installed binary)
~/.undertow/bin/UndertowHelper → symlink to above             (no-spaces path)
```

Post-build script in Project.swift auto-copies, re-signs, and creates symlink on every UndertowHelper build.

---

## Phase 0: Foundation & Scaffolding — COMPLETE

### What was built:
- 6 Tuist targets building successfully
- MCP server (`--mcp` mode) with stdio transport
- Hook handler (`--hook` mode) for git context gathering
- XPC controller for background service mode (default mode)
- Shared XPC protocols and models in UndertowKit
- Source Editor Extension with PingCommand
- `.claude.json` configured with MCP server for undertow project
- Post-build script for auto-install + re-sign + symlink
- 48 tests (UndertowTests scheme) including 12 integration tests

### MCP Tools registered:
1. `hello` — Server health check
2. `get_flow_context` — Hybrid git snapshot + observer data
3. `semantic_search` — Natural language + symbol codebase search
4. `find_symbol_references` — Compiler index symbol lookup
5. `find_conformances` — Protocol conformance discovery

### Key files:
- `Sources/UndertowHelper/main.swift` — Entry point with 3 modes (MCP, hook, XPC)
- `Sources/UndertowHelper/MCPServer.swift` — MCP server with all tool definitions
- `Sources/UndertowHelper/Flow/GitContextProvider.swift` — Git snapshot + hybrid context
- `Sources/UndertowHelper/Tools/SemanticSearchTool.swift` — Search engine actor
- `Sources/UndertowTests/TestHarness.swift` — Subprocess-based test harness
- `Sources/UndertowTests/HelperIntegrationTests.swift` — 7 hook integration tests
- `CLAUDE.md` — Instructions for Xcode Coding Assistant to use Undertow tools
- `SKILL.md` — Placeholder for future skills

---

## Phase 1: Flow Engine — Real-Time Activity Awareness

### 1.1 — Git Context Provider — COMPLETE
- `GitContextProvider.gatherFlowContext()` — git branch, status, diff stats, recent commits
- `GitContextProvider.gatherHybridContext()` — git snapshot + persisted observer data
- `GitContextProvider.findRecentlyModifiedFiles()` — filesystem scan by mtime
- All functions use `Subprocess`, not `Foundation.Process`
- Exposed via `get_flow_context` MCP tool

### 1.2 — Build Log Observer — COMPLETE
- Watches `DerivedData/<project>/Logs/Build/` for `.xcactivitylog` files
- Parses gzip-compressed build logs (0-byte filter + Subprocess gunzip)
- Extracts success/failure, error messages, warning counts
- Stores as `BuildStatus` struct

### 1.3 — File System Observer — COMPLETE
- `Sources/UndertowHelper/Flow/FileSystemObserver.swift`
- FSEvents with 1s debounce, filters hidden/build dirs, deduplicates within 2s
- Rolling buffer: last 50 events or 10 minutes
- Wired into `get_flow_context` via `gatherHybridContext(fileObserver:)`
- Output includes `[File Activity]` section with event type and relative path

### 1.4 — Xcode State Observer (Accessibility API) — STUBBED
**Files:**
- `Sources/UndertowHelper/Flow/XcodeObserver.swift`
- `Sources/UndertowHelper/Flow/AXNotificationStream.swift`
- `Sources/UndertowHelper/Flow/AXExtensions.swift`

**TODO:**
- `AXObserver` with `AsyncSequence` streaming (not polling)
- Track: active file, cursor position, active scheme, workspace URL
- Subscribe to: `kAXSelectedTextChangedNotification`, `kAXValueChangedNotification`, `kAXFocusedUIElementChangedNotification`
- Does NOT need XPC — runs directly in UndertowHelper process
- Requires Accessibility permission (`AXIsProcessTrusted()`)

### 1.5 — Flow Context Aggregator — REMOVED
Deleted `FlowContextAggregator.swift`. Its continuous stream-merging + disk persistence model was designed for a background daemon feeding short-lived clients, but MCP is pull-based — the tool queries each observer on demand. The `resolveProject()` utility was moved to `GitContextProvider`. XPCController updated to call `GitContextProvider.gatherHybridContext()` directly.

### 1.6 — Context Delivery via MCP — COMPLETE
Instead of hooks (which don't work in Xcode), flow context is delivered via:
1. **`get_flow_context` MCP tool** — Agent calls on demand
2. **CLAUDE.md** — Instructs agent to call `get_flow_context` at session start
3. **Hybrid model** — Git snapshot is always fresh; observer data is included when the background service is running and has persisted recent context

---

## Phase 2: Semantic Relevance Engine — COMPLETE

### 2.1 — Code Chunker (SwiftSyntax) — COMPLETE
- `Sources/UndertowKit/Indexing/CodeChunker.swift`
- `Sources/UndertowKit/Indexing/SwiftChunkVisitor.swift`
- Parses `.swift` files, extracts chunks at function/type/extension level
- 330 chunks indexed for the Undertow project

### 2.2 — IndexStoreDB Integration — COMPLETE
- `Sources/UndertowHelper/Indexing/IndexStoreService.swift`
- Loads compiler index from DerivedData
- `findSymbolReferences()`, `findConformances()`, `searchSymbols()`
- Exposed as MCP tools: `find_symbol_references`, `find_conformances`
- Migrated from Foundation.Process to Subprocess

### 2.3 — On-Device Relevance Scorer — COMPLETE (with fallback)
- `Sources/UndertowHelper/Relevance/RelevanceScorer.swift`
- Foundation Models for semantic re-ranking when available
- BM25 text search as fallback

### 2.4 — Hybrid Retrieval MCP Tool — COMPLETE
- `Sources/UndertowHelper/Tools/SemanticSearchTool.swift`
- `semantic_search(query:)` — structural (IndexStoreDB) + semantic (BM25/FM) + dedup
- Exposed as MCP tool

### 2.5 — Importance Map — COMPLETE
- `Sources/UndertowHelper/Relevance/ImportanceMap.swift`
- Git churn analysis (last 30 days), edit frequency weighting
- Uses Subprocess for git commands

---

## Phase 3: Setup & Onboarding GUI — COMPLETE

The host app provides a setup/management interface so users can install, configure, and verify Undertow without manual file editing. The app is **sandboxed** (App Store) and uses **security-scoped bookmarks** for filesystem access.

### 3.1 — Models — COMPLETE
- `SetupStatusReport`, `ProjectConfig`, `ConfigTarget`, `VerificationResult` in UndertowKit
- `ConfigManager` in UndertowKit — testable config I/O with injectable `home: URL`
- `BookmarkManager` in UndertowKit — security-scoped bookmark persistence with access state

### 3.2 — Config Operations (Sandboxed + Bookmarks) — COMPLETE
- `ConfigManager` in UndertowKit handles all filesystem operations directly
- JSON config I/O using `JSONSerialization` (preserves unknown keys from other tools)
- Reads Xcode config only (`~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude.json`) — Undertow is Xcode-only
- MCP server verification: filesystem-only config validation (checks entry exists, command binary exists via `fileExists`, symlink intact, --mcp arg present, PROJECT_DIR matches)
- Helper installation: copies from app bundle, code-signs, creates symlink
- Uses `getpwuid(getuid())` for real home directory (not sandbox container)
- `BookmarkManager` stores security-scoped bookmark to home directory in app group UserDefaults

### 3.3 — App UI — COMPLETE
- `SettingsView` — `TabView` with two tabs: Projects + Permissions
- `ProjectsSection` — Combined status header (Undertow branding + health) + "Grant Access" prompt when bookmark not granted + MCP server health (shown only when unhealthy) + project list with per-project verify/remove
- `ProjectRow` + `AddProjectSheet` — Add/remove/verify projects (Xcode-only, no checkboxes)
- `PermissionsSection` — Home Folder Access (grant/revoke via `fileImporter`) + Accessibility + Extension permission status
- `SetupManager` — `@Observable` class wrapping `ConfigManager` + `BookmarkManager`, access state guards on all operations
- `MenuBarPopover` — Menu bar with health dot (checks both access state + helper installed)
- `StatusBadge` — Reusable capsule badge component
- Uses `fileImporter` (not `NSOpenPanel`) to avoid layout recursion warnings

### 3.4 — Tests — COMPLETE (75 tests)
- Config I/O tests (read/write/round-trip with injectable home directory)
- Setup status tests (helper detection, symlink validation)
- Bookmark state tests (initial, restore, revoke, grant-revoke cycle)
- Project verification tests (7 tests: no config entry, missing binary, valid config, broken symlink, missing --mcp arg, mismatched PROJECT_DIR, finds Claude Code entry)

---

## Phase 4: Persistent Memory System — NOT STARTED

### 4.1 — Memory Store
- Store memories as JSON in `.undertow/memories.json`
- CRUD operations exposed as MCP tools: `get_memories(query:)`, `save_memory(content:tags:)`

### 4.2 — Memory Relevance Retrieval
- Score memories against query using Foundation Models
- User-created memories injected unconditionally (project rules)
- Auto-generated memories scored and top-k injected

### 4.3 — Auto-Memory Detection
- After agent interactions, detect reusable facts/conventions
- Use Foundation Models for extraction
- Notification for user approval before saving

### 4.4 — CLAUDE.md Sync
- Optionally write user memories to CLAUDE.md
- Parse existing CLAUDE.md on load
- Bidirectional sync with conflict detection

---

## Phase 5: Checkpoints & Reverts — NOT STARTED

### 5.1 — Auto-Checkpoint
- Before file modifications, create git checkpoint on shadow branch `undertow/checkpoints`
- Trigger via MCP tool (not hooks, since hooks unavailable in Xcode)

### 5.2 — Named Checkpoints MCP Tool
- `create_checkpoint(name:)`, `list_checkpoints()`, `revert_to_checkpoint(name:)`
- Git tag based: `undertow-cp/{name}`

### 5.3 — Checkpoint Browser UI
- SwiftUI list in host app with diff viewer and one-click revert

---

## Phase 6: Auto-Lint and Build Loop — NOT STARTED

### 6.1 — Auto-Lint
- MCP tool to run `swiftlint` on changed files
- Agent can invoke after edits

### 6.2 — Auto-Build
- MCP tool to trigger background build
- Return structured build errors (file, line, message)

### 6.3 — Test Runner MCP Tool
- `run_tests(target:filter:)` via `xcodebuild test` or Xcode MCP

---

## Phase 7: Inline Completions & Command Mode (Optional) — NOT STARTED

### 7.1 — Source Editor Extension: Command Mode
- Commands: InlineEdit (⌘+I), Explain, Refactor, AddTests
- Requires XPC/Bridge layer (only use case for it)

### 7.2 — Inline Completion Overlay
- AX-positioned overlay at cursor in Xcode editor
- Foundation Models for fast on-device completions

---

## Dependency Summary

| Package | Purpose | Target |
|---------|---------|--------|
| `modelcontextprotocol/swift-sdk` | MCP server implementation | UndertowKit |
| `swiftlang/swift-syntax` | Code chunking, AST parsing | UndertowKit |
| `swiftlang/indexstore-db` | Compiler-level symbol index | UndertowHelper |
| `apple/swift-subprocess` | Process execution (replaces Foundation.Process) | UndertowHelper, UndertowTests |
| `21-DOT-DEV/swift-plugin-tuist` | Project generation | Package plugin |

---

## Reference Codebases

- `~/Developer/CopilotForXcode/` — XPC, bridge, AX observation patterns
- `~/Developer/XcodeCopilot/` — SwiftSyntax code chunking, AST parsing
- `~/Developer/subtree/` — Subprocess patterns, integration test harness

---

## Open Questions

1. ~~**Strip XPC/Bridge?**~~ — **RESOLVED: Keep for Extension path only.** Setup operations use direct filesystem access via security-scoped bookmarks (no XPC needed). Bridge XPC is kept only for Extension → Helper communication.
2. **Background service mode** — Currently UndertowHelper has a default mode that starts XPC controller. If XPC is stripped, this mode needs redesign (LaunchAgent? Manual start?).
3. **Observer data persistence** — Where/how should background observers persist FlowContext for the MCP server to read? Currently planned as JSON file in app group container.

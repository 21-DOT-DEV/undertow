import Foundation
import UndertowKit

/// UndertowHelper: Background agent providing MCP tools, flow engine,
/// relevance scoring, and memory management.
///
/// Modes:
///   (no args)  — Background XPC service mode
///   --mcp      — MCP server mode (stdio transport)
///   --hook <event> — Hook handler mode (stdin JSON → stdout JSON)

let arguments = CommandLine.arguments

if arguments.contains("--mcp") {
    // MCP server mode: communicate via stdio
    let server = UndertowMCPServer()
    Task {
        do {
            try await server.start()
        } catch {
            fputs("MCP server error: \(error)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()

} else if let hookIndex = arguments.firstIndex(of: "--hook"),
          hookIndex + 1 < arguments.count {
    // Hook handler mode: read JSON from stdin, write response to stdout
    let eventName = arguments[hookIndex + 1]
    _ = FileHandle.standardInput.readDataToEndOfFile()

    switch eventName {
    case "user-prompt-submit":
        // Read the latest flow context from the shared file
        let contextSummary: String
        if let data = try? Data(contentsOf: UndertowXPC.flowContextFile),
           let context = try? JSONDecoder().decode(FlowContext.self, from: data) {
            // Check staleness — ignore context older than 30 seconds
            if Date.now.timeIntervalSince(context.timestamp) < 30 {
                contextSummary = formatFlowContext(context)
            } else {
                contextSummary = "[Undertow] Flow context stale (background service may not be running)."
            }
        } else {
            contextSummary = "[Undertow] No flow context available. Ensure the helper is running."
        }

        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "UserPromptSubmit",
                "additionalContext": contextSummary
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            FileHandle.standardOutput.write(data)
        }

    default:
        // Unknown hook event — pass through
        break
    }

} else {
    // Background service mode: set up XPC listener and register with bridge
    let controller = XPCController()
    controller.start()
    RunLoop.main.run()
}

// MARK: - Flow Context Formatting

/// Format a `FlowContext` as a concise summary string for hook injection.
func formatFlowContext(_ ctx: FlowContext) -> String {
    var parts: [String] = []

    if let file = ctx.activeFile {
        let fileName = (file as NSString).lastPathComponent
        var fileInfo = "Active file: \(fileName)"
        if let line = ctx.cursorLine {
            fileInfo += " (line \(line))"
        }
        parts.append(fileInfo)
    }

    if let build = ctx.buildStatus {
        if build.succeeded {
            parts.append("Last build: succeeded")
        } else {
            var buildInfo = "Last build: FAILED (\(build.errorCount) error\(build.errorCount == 1 ? "" : "s")"
            if build.warningCount > 0 {
                buildInfo += ", \(build.warningCount) warning\(build.warningCount == 1 ? "" : "s")"
            }
            buildInfo += ")"
            if !build.errors.isEmpty {
                let errorList = build.errors.prefix(3).map { "  - \($0)" }.joined(separator: "\n")
                buildInfo += "\n\(errorList)"
            }
            parts.append(buildInfo)
        }
    }

    if !ctx.recentEdits.isEmpty {
        let editPaths = ctx.recentEdits.prefix(5).map {
            ($0.path as NSString).lastPathComponent
        }
        let unique = editPaths.removingDuplicates()
        parts.append("Recent edits: \(unique.joined(separator: ", "))")
    }

    if !ctx.recentNavigation.isEmpty {
        let navPaths = ctx.recentNavigation.prefix(5).map {
            ($0 as NSString).lastPathComponent
        }
        let unique = navPaths.removingDuplicates()
        parts.append("Recently visited: \(unique.joined(separator: ", "))")
    }

    if let scheme = ctx.activeScheme {
        var schemeInfo = "Scheme: \(scheme)"
        if let dest = ctx.activeDestination {
            schemeInfo += " → \(dest)"
        }
        parts.append(schemeInfo)
    }

    if parts.isEmpty {
        return "[Undertow] Flow context: no active Xcode session detected."
    }

    return "[Undertow Flow Context]\n" + parts.joined(separator: "\n")
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

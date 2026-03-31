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
    let inputData = FileHandle.standardInput.readDataToEndOfFile()

    switch eventName {
    case "user-prompt-submit":
        // Phase 0: minimal hook that logs and returns empty context
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "UserPromptSubmit",
                "additionalContext": "[Undertow] Hook active. Flow context not yet implemented."
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

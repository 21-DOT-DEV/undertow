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
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("[\(timestamp)] Undertow hook fired: \(eventName)\n", stderr)
    _ = FileHandle.standardInput.readDataToEndOfFile()

    switch eventName {
    case "user-prompt-submit":
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let context = await GitContextProvider.gatherFlowContext()
            fputs(context, stdout)
            semaphore.signal()
        }
        semaphore.wait()

    default:
        break
    }

} else {
    // Background service mode: set up XPC listener and register with bridge
    let controller = XPCController()
    controller.start()
    RunLoop.main.run()
}



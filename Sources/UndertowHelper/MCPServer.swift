import Foundation
import MCP

/// MCP server exposing Undertow tools to Xcode's Claude Agent.
final class UndertowMCPServer: Sendable {
    private let server: Server

    init() {
        server = Server(
            name: "undertow",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
    }

    func start() async throws {
        let helloTool = Tool(
            name: "hello",
            description: "Verifies the Undertow MCP server is running. Returns a greeting.",
            inputSchema: .object(properties: [:])
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [helloTool])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "hello":
                return .init(content: [.text("Hello from Undertow! MCP server is operational.")])
            default:
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

import Foundation
import MCP
import UndertowKit

/// MCP server exposing Undertow tools to Xcode's Claude Agent.
final class UndertowMCPServer: Sendable {
    private let server: Server
    private let searchEngine = SemanticSearchEngine()

    init() {
        server = Server(
            name: "undertow",
            version: "0.2.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
    }

    func start() async throws {
        // Initialize the search engine from workspace context
        let projectPath = detectProjectPath()
        let (projectRoot, projectName) = FlowContextAggregator.resolveProject(path: projectPath)
        await searchEngine.initialize(projectRoot: projectRoot, projectName: projectName)

        // Tool definitions
        let helloTool = Tool(
            name: "hello",
            description: "Verifies the Undertow MCP server is running. Returns a greeting.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )

        let allTools = [helloTool, SemanticSearchEngine.toolDefinition]
            + SemanticSearchEngine.indexToolDefinitions

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: allTools)
        }

        let engine = searchEngine
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "hello":
                return .init(content: [.text(text: "Hello from Undertow! MCP server is operational.", annotations: nil, _meta: nil)])
            case "semantic_search", "find_symbol_references", "find_conformances":
                let content = try await engine.handleToolCall(
                    name: params.name,
                    arguments: params.arguments
                )
                return .init(content: content)
            default:
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    private func detectProjectPath() -> String {
        // Check for common environment variables or fall back to cwd
        if let pwd = ProcessInfo.processInfo.environment["PROJECT_DIR"] {
            return pwd
        }
        return FileManager.default.currentDirectoryPath
    }
}

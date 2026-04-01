import Foundation
import MCP
import UndertowKit

/// MCP server exposing Undertow tools to Xcode's Claude Agent.
final class UndertowMCPServer: Sendable {
    private let server: Server
    private let searchEngine = SemanticSearchEngine()
    private let buildObserver = BuildLogObserver()

    init() {
        server = Server(
            name: "undertow",
            version: "0.2.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
    }

    func start() async throws {
        // Initialize from workspace context
        let projectPath = detectProjectPath()
        let (projectRoot, projectName) = FlowContextAggregator.resolveProject(path: projectPath)
        await searchEngine.initialize(projectRoot: projectRoot, projectName: projectName)

        // Start background observers
        await buildObserver.start(projectName: projectName)

        // Tool definitions
        let helloTool = Tool(
            name: "hello",
            description: "Verifies the Undertow MCP server is running. Returns a greeting.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )

        let flowContextTool = Tool(
            name: "get_flow_context",
            description: "Returns the developer's current flow context: git branch, uncommitted changes, diff stats, recent commits, recently modified files, and any available Xcode observer data (active file, build status, scheme). Call this at the start of each conversation to understand what the developer is working on.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        )

        let allTools = [helloTool, flowContextTool, SemanticSearchEngine.toolDefinition]
            + SemanticSearchEngine.indexToolDefinitions

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: allTools)
        }

        let engine = searchEngine
        let projectDir = projectPath
        let buildObs = buildObserver
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "hello":
                return .init(content: [.text(text: "Hello from Undertow! MCP server is operational.", annotations: nil, _meta: nil)])
            case "get_flow_context":
                let context = await GitContextProvider.gatherHybridContext(
                    projectDir: projectDir,
                    buildObserver: buildObs
                )
                return .init(content: [.text(text: context, annotations: nil, _meta: nil)])
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

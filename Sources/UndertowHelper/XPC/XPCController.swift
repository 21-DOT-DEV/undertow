import AppKit
import ApplicationServices
import Foundation
import UndertowKit

/// Manages the helper's XPC listener, bridge connection, and flow engine.
///
/// Creates an anonymous XPC listener and registers its endpoint with
/// the bridge. Pings the bridge every 60 seconds to stay alive.
/// Owns the `FlowContextAggregator` shared by XPC handlers and hook mode.
final class XPCController: NSObject {
    private let xpcListener = NSXPCListener.anonymous()
    private var bridgeConnection: NSXPCConnection?
    private var pingTask: Task<Void, Never>?

    /// The shared flow context aggregator.
    let aggregator = FlowContextAggregator()

    /// The shared semantic search engine.
    let searchEngine = SemanticSearchEngine()

    override init() {
        super.init()
        xpcListener.delegate = self
    }

    func start() {
        xpcListener.resume()
        connectToBridge()
        startPingTask()
        startFlowEngine()
    }

    private func startFlowEngine() {
        Task {
            // Detect the project path from Xcode's active workspace
            // or fall back to the current working directory
            let projectPath = await detectProjectPath()
            await aggregator.start(projectPath: projectPath)
            await searchEngine.initialize(projectRoot: projectPath)
        }
    }

    @MainActor
    private func detectProjectPath() async -> String {
        // Try to get workspace from Xcode via AX
        if let xcode = NSWorkspace.shared.runningApplications.first(where: \.isXcode) {
            let appElement = AXUIElementCreateApplication(xcode.processIdentifier)
            if let window = appElement.focusedWindow ?? appElement.mainWindow,
               let path = window.extractWorkspacePath() {
                return path
            }
        }
        // Fallback to current directory
        return FileManager.default.currentDirectoryPath
    }

    // MARK: - Bridge Connection

    private func connectToBridge() {
        let connection = NSXPCConnection(machServiceName: UndertowXPC.bridgeServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: BridgeXPCProtocol.self)
        connection.invalidationHandler = { [weak self] in
            self?.bridgeConnection = nil
            // Reconnect after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.connectToBridge()
            }
        }
        connection.resume()
        bridgeConnection = connection

        // Register our endpoint with the bridge
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            fputs("Bridge XPC error: \(error)\n", stderr)
        } as? BridgeXPCProtocol

        proxy?.updateHelperEndpoint(xpcListener.endpoint) {
            fputs("Helper endpoint registered with bridge.\n", stderr)
        }
    }

    private func startPingTask() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, let connection = self.bridgeConnection else { continue }
                let proxy = connection.remoteObjectProxyWithErrorHandler { _ in }
                    as? BridgeXPCProtocol
                proxy?.ping {}
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension XPCController: NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = HelperXPCService(aggregator: aggregator, searchEngine: searchEngine)
        newConnection.invalidationHandler = { [weak newConnection] in
            newConnection?.invalidationHandler = nil
        }
        newConnection.resume()
        return true
    }
}

// MARK: - HelperXPCProtocol Implementation

private final class HelperXPCService: NSObject, HelperXPCProtocol {
    private let aggregator: FlowContextAggregator
    private let searchEngine: SemanticSearchEngine

    init(aggregator: FlowContextAggregator, searchEngine: SemanticSearchEngine) {
        self.aggregator = aggregator
        self.searchEngine = searchEngine
        super.init()
    }

    func getFlowContext(withReply reply: @escaping (Data?, (any Error)?) -> Void) {
        Task {
            do {
                let data = try await aggregator.contextData()
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    func semanticSearch(query: Data, withReply reply: @escaping (Data?, (any Error)?) -> Void) {
        Task {
            do {
                guard let queryString = String(data: query, encoding: .utf8) else {
                    reply(nil, nil)
                    return
                }
                let results = await searchEngine.search(query: queryString)
                let data = try JSONEncoder().encode(results)
                reply(data, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    func getMemories(query: Data, withReply reply: @escaping (Data?, (any Error)?) -> Void) {
        // TODO: Phase 3
        reply(nil, nil)
    }

    func saveMemory(content: Data, withReply reply: @escaping ((any Error)?) -> Void) {
        // TODO: Phase 3
        reply(nil)
    }

    func createCheckpoint(name: String, withReply reply: @escaping ((any Error)?) -> Void) {
        // TODO: Phase 4
        reply(nil)
    }

    func listCheckpoints(withReply reply: @escaping (Data?, (any Error)?) -> Void) {
        // TODO: Phase 4
        reply(nil, nil)
    }

    func revertToCheckpoint(name: String, withReply reply: @escaping ((any Error)?) -> Void) {
        // TODO: Phase 4
        reply(nil)
    }

    func ping(withReply reply: @escaping () -> Void) {
        reply()
    }
}

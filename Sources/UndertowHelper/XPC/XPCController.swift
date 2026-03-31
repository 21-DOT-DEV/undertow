import Foundation
import UndertowKit

/// Manages the helper's XPC listener and bridge connection.
///
/// Creates an anonymous XPC listener and registers its endpoint with
/// the bridge. Pings the bridge every 60 seconds to stay alive.
final class XPCController: NSObject {
    private let xpcListener = NSXPCListener.anonymous()
    private var bridgeConnection: NSXPCConnection?
    private var pingTask: Task<Void, Never>?

    override init() {
        super.init()
        xpcListener.delegate = self
    }

    func start() {
        xpcListener.resume()
        connectToBridge()
        startPingTask()
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
        newConnection.exportedObject = HelperXPCService()
        newConnection.invalidationHandler = { [weak newConnection] in
            newConnection?.invalidationHandler = nil
        }
        newConnection.resume()
        return true
    }
}

// MARK: - HelperXPCProtocol Implementation

private final class HelperXPCService: NSObject, HelperXPCProtocol {
    func getFlowContext(withReply reply: @escaping (Data?, (any Error)?) -> Void) {
        // TODO: Phase 1 — Return actual flow context
        let context = FlowContext()
        let data = try? JSONEncoder().encode(context)
        reply(data, nil)
    }

    func semanticSearch(query: Data, withReply reply: @escaping (Data?, (any Error)?) -> Void) {
        // TODO: Phase 2
        reply(nil, nil)
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

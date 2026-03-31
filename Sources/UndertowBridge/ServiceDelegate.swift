import Foundation
import UndertowKit

/// Accepts incoming XPC connections and implements the bridge protocol.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    /// The helper's anonymous XPC listener endpoint, if registered.
    private var helperEndpoint: NSXPCListenerEndpoint?

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: BridgeXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak newConnection] in
            newConnection?.invalidationHandler = nil
        }
        newConnection.resume()
        return true
    }
}

// MARK: - BridgeXPCProtocol

extension ServiceDelegate: BridgeXPCProtocol {
    func launchHelperIfNeeded(withReply reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        if let endpoint = helperEndpoint {
            reply(endpoint)
            return
        }

        // TODO: Phase 0.8 — Launch helper from app bundle if not running
        reply(nil)
    }

    func updateHelperEndpoint(
        _ endpoint: NSXPCListenerEndpoint,
        withReply reply: @escaping () -> Void
    ) {
        helperEndpoint = endpoint
        reply()
    }

    func ping(withReply reply: @escaping () -> Void) {
        reply()
    }
}

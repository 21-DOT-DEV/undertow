import Foundation

/// XPC protocol implemented by the UndertowBridge mach service.
///
/// The bridge acts as a lightweight forwarder between the Source Editor extension
/// and the non-sandboxed UndertowHelper for runtime communication.
/// Setup and configuration operations are handled directly by the host app
/// via security-scoped bookmarks (see SetupManager).
@objc public protocol BridgeXPCProtocol {
    /// Returns the helper's XPC listener endpoint, launching the helper if needed.
    func launchHelperIfNeeded(withReply reply: @escaping (NSXPCListenerEndpoint?) -> Void)

    /// Called by the helper to register its anonymous XPC listener endpoint.
    func updateHelperEndpoint(_ endpoint: NSXPCListenerEndpoint, withReply reply: @escaping () -> Void)

    /// Health check. Returns immediately if the bridge is alive.
    func ping(withReply reply: @escaping () -> Void)
}

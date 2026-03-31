import Foundation

/// XPC protocol implemented by the UndertowBridge mach service.
///
/// The bridge acts as a lightweight forwarder between sandboxed components
/// (host app, extension) and the non-sandboxed UndertowHelper.
@objc public protocol BridgeXPCProtocol {
    /// Returns the helper's XPC listener endpoint, launching the helper if needed.
    func launchHelperIfNeeded(withReply reply: @escaping (NSXPCListenerEndpoint?) -> Void)

    /// Called by the helper to register its anonymous XPC listener endpoint.
    func updateHelperEndpoint(_ endpoint: NSXPCListenerEndpoint, withReply reply: @escaping () -> Void)

    /// Health check. Returns immediately if the bridge is alive.
    func ping(withReply reply: @escaping () -> Void)
}

import Foundation

/// Shared constants for XPC communication between Undertow components.
public enum UndertowXPC {
    /// App Group identifier shared by all Undertow targets.
    public static let appGroup = "group.dev.21.Undertow"

    /// Mach service name for the communication bridge.
    public static let bridgeServiceName = "dev.21.Undertow.Bridge"
}

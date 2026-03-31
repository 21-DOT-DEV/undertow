import Foundation

/// Shared constants for XPC communication between Undertow components.
public enum UndertowXPC {
    /// App Group identifier shared by all Undertow targets.
    public static let appGroup = "group.dev.21.Undertow"

    /// Mach service name for the communication bridge.
    public static let bridgeServiceName = "dev.21.Undertow.Bridge"

    /// Directory for shared state files (flow context, etc.).
    public static var sharedStateDirectory: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Undertow")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Path to the flow context JSON file written by the background service.
    public static var flowContextFile: URL {
        sharedStateDirectory.appendingPathComponent("flow-context.json")
    }
}

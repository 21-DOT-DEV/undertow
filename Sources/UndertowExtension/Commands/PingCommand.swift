import Foundation
import XcodeKit
import UndertowKit

/// A minimal command that verifies communication with the Undertow bridge.
struct PingCommand: UndertowCommand {
    let className = "$(PRODUCT_MODULE_NAME).PingCommandHandler"
    let identifier = "dev.21.Undertow.Extension.Ping"
    let name = "Undertow: Ping"
}

/// Handler for the ping command.
class PingCommandHandler: NSObject, XCSourceEditorCommand {
    func perform(
        with invocation: XCSourceEditorCommandInvocation,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let connection = NSXPCConnection(machServiceName: UndertowXPC.bridgeServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: BridgeXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            completionHandler(error)
        } as? BridgeXPCProtocol

        proxy?.ping {
            // Insert a comment at the top to confirm the ping worked
            invocation.buffer.lines.insert(
                "// Undertow: Bridge connection verified",
                at: 0
            )
            completionHandler(nil)
        }
    }
}

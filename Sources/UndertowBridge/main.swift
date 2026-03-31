import Foundation
import UndertowKit

/// UndertowBridge: Lightweight mach service forwarder.
///
/// Registers a mach service that sandboxed components (host app, extension)
/// can connect to. Forwards requests to UndertowHelper via its anonymous
/// XPC listener endpoint.

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: UndertowXPC.bridgeServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()

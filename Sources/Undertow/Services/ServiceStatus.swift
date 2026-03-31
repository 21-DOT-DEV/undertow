import Foundation
import Observation
import UndertowKit

/// Observable state tracking the status of Undertow's background services.
@Observable
final class ServiceStatus {
    var bridgeConnected = false
    var helperConnected = false
    var accessibilityGranted = false

    init() {
        Task { await checkServices() }
    }

    @MainActor
    func checkServices() async {
        let bridge = NSXPCConnection(machServiceName: UndertowXPC.bridgeServiceName)
        bridge.remoteObjectInterface = NSXPCInterface(with: BridgeXPCProtocol.self)
        bridge.resume()

        let reachable = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let proxy = bridge.remoteObjectProxyWithErrorHandler { _ in
                cont.resume(returning: false)
            } as? BridgeXPCProtocol

            guard let proxy else {
                cont.resume(returning: false)
                return
            }

            proxy.ping {
                cont.resume(returning: true)
            }
        }

        bridgeConnected = reachable
        bridge.invalidate()
    }
}

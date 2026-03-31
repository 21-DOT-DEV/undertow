import SwiftUI
import UndertowKit

@main
struct UndertowApp: App {
    @State private var serviceStatus = ServiceStatus()

    var body: some Scene {
        WindowGroup {
            ContentView(serviceStatus: serviceStatus)
        }

        MenuBarExtra("Undertow", systemImage: "water.waves") {
            VStack(alignment: .leading) {
                Label(
                    serviceStatus.bridgeConnected ? "Bridge: Connected" : "Bridge: Disconnected",
                    systemImage: serviceStatus.bridgeConnected ? "checkmark.circle.fill" : "xmark.circle"
                )
                Label(
                    serviceStatus.helperConnected ? "Helper: Connected" : "Helper: Disconnected",
                    systemImage: serviceStatus.helperConnected ? "checkmark.circle.fill" : "xmark.circle"
                )
                Divider()
                Button("Quit Undertow") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
        }
    }
}

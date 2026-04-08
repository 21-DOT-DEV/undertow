import SwiftUI

@main
struct UndertowApp: App {
    @State private var serviceStatus = ServiceStatus()
    @State private var setupManager = SetupManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Undertow", systemImage: "water.waves") {
            MenuBarPopover(
                serviceStatus: serviceStatus,
                setupManager: setupManager,
                onOpenSettings: { openSettingsWindow() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .menuBarExtraStyle(.window)

        Window("Undertow Settings", id: "settings") {
            SettingsView(
                serviceStatus: serviceStatus,
                setupManager: setupManager
            )
            .onAppear { NSApp.setActivationPolicy(.regular) }
            .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 560, height: 480)
    }

    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

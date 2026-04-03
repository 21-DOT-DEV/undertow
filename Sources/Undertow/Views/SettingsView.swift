import SwiftUI

/// Settings window with tabbed sections for managing Undertow.
struct SettingsView: View {
    var serviceStatus: ServiceStatus
    var setupManager: SetupManager

    var body: some View {
        TabView {
            Tab("Projects", systemImage: "folder.badge.gearshape") {
                ProjectsSection(
                    serviceStatus: serviceStatus,
                    setupManager: setupManager
                )
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsSection(serviceStatus: serviceStatus)
            }
        }
        .onAppear {
            serviceStatus.refreshAll(using: setupManager)
        }
    }
}

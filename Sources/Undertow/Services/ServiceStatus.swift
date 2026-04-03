import Foundation
import Observation
import UndertowKit

/// Observable state tracking the status of Undertow's setup.
@Observable
final class ServiceStatus {
    var helperInstalled = false
    var symlinkValid = false
    var accessibilityGranted = false

    /// Configured project paths from the Xcode config file.
    var configuredProjects: [ProjectConfig] = []

    // MARK: - Refresh

    /// Refreshes all status checks using the SetupManager.
    @MainActor
    func refreshAll(using manager: SetupManager) {
        let status = manager.getSetupStatus()
        helperInstalled = status.helperInstalled
        symlinkValid = status.symlinkValid

        configuredProjects = status.xcodeConfiguredProjects.map { path in
            ProjectConfig(path: path, xcodeConfigured: true)
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        accessibilityGranted = manager.checkAccessibility()
    }
}

import AppKit
import SwiftUI
import UndertowKit

/// Permission status and links to System Settings.
struct PermissionsSection: View {
    var serviceStatus: ServiceStatus
    var setupManager: SetupManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                homeFolderGroup
                accessibilityGroup
                extensionGroup
            }
            .padding()
        }
        .navigationTitle("Permissions")
        .frame(minWidth: 480)
    }

    // MARK: - Home Folder Access

    private var homeFolderGroup: some View {
        GroupBox("Home Folder Access") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: setupManager.accessState == .accessGranted
                          ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(setupManager.accessState == .accessGranted
                                         ? .green : .secondary)
                    Text("Home Folder")
                    Spacer()
                    StatusBadge(
                        text: homeFolderStatusText,
                        level: setupManager.accessState == .accessGranted ? .success : .warning
                    )
                }

                Text("Required to read and write MCP configuration files in your home directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if setupManager.accessState != .accessGranted {
                    if setupManager.bookmarkManager.hasStoredBookmark {
                        Text("A previous bookmark exists. Click Restore to reactivate it, or Grant Access to select a new folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Restore Access") {
                                setupManager.restoreBookmark()
                                serviceStatus.refreshAll(using: setupManager)
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)

                            Button("Grant Access\u{2026}") {
                                presentHomeFolderPicker()
                            }
                            .controlSize(.small)
                        }
                    } else {
                        Text("Select your home folder to grant Undertow access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Grant Access\u{2026}") {
                            presentHomeFolderPicker()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Revoke Access") {
                        setupManager.revokeAccess()
                        serviceStatus.refreshAll(using: setupManager)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var homeFolderStatusText: String {
        switch setupManager.accessState {
        case .accessGranted: "Granted"
        case .bookmarkStale: "Expired"
        case .noBookmark: "Not Granted"
        }
    }

    // MARK: - Accessibility

    private var accessibilityGroup: some View {
        GroupBox("Accessibility") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: serviceStatus.accessibilityGranted
                          ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(serviceStatus.accessibilityGranted ? .green : .secondary)
                    Text("Accessibility Permission")
                    Spacer()
                    StatusBadge(
                        text: serviceStatus.accessibilityGranted ? "Granted" : "Not Granted",
                        level: serviceStatus.accessibilityGranted ? .success : .warning
                    )
                }

                Text("Required for Xcode state observation — tracks active file, cursor position, and editor context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !serviceStatus.accessibilityGranted {
                    Button("Open Accessibility Settings") {
                        openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Extension

    private var extensionGroup: some View {
        GroupBox("Source Editor Extension") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                    Text("Xcode Extension")
                    Spacer()
                    StatusBadge(text: "Optional", level: .info)
                }

                Text("Enable in System Settings > General > Login Items & Extensions > Xcode Source Editor to use inline commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Extension Settings") {
                    openExtensionSettings()
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Home Folder Picker

    private func presentHomeFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = "Select your home folder to grant Undertow access to MCP configuration files."
        // Open at /Users/ so the user's home folder is visible and selectable.
        panel.directoryURL = ConfigManager.realHomeDirectory.deletingLastPathComponent()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            setupManager.grantAccess(to: url)
            serviceStatus.refreshAll(using: setupManager)
        }
    }

    // MARK: - System Settings Links

    private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openExtensionSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}

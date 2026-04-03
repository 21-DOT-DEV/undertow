import SwiftUI

/// Permission status and links to System Settings.
struct PermissionsSection: View {
    var serviceStatus: ServiceStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                accessibilityGroup
                extensionGroup
            }
            .padding()
        }
        .navigationTitle("Permissions")
        .frame(minWidth: 480)
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

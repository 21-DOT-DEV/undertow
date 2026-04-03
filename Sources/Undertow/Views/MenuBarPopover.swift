import SwiftUI
import UndertowKit

/// Menu bar popover showing per-project health at a glance.
struct MenuBarPopover: View {
    var serviceStatus: ServiceStatus
    var setupManager: SetupManager
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            if serviceStatus.configuredProjects.isEmpty {
                emptyState
                    .padding(12)
            } else {
                projectList
            }

            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "water.waves")
                .foregroundStyle(.tint)
            Text("Undertow")
                .font(.headline)
            Spacer()
            Circle()
                .fill(serviceStatus.helperInstalled ? .green : .orange)
                .frame(width: 8, height: 8)
                .help(serviceStatus.helperInstalled ? "All systems operational" : "Setup incomplete")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No projects configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open Settings to add a project.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Project List

    private var projectList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(serviceStatus.configuredProjects) { project in
                    PopoverProjectRow(project: project)
                    if project.id != serviceStatus.configuredProjects.last?.id {
                        Divider()
                            .padding(.leading, 32)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Settings...") {
                onOpenSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .font(.subheadline)

            Spacer()

            Button("Quit") {
                onQuit()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }
}

// MARK: - Popover Project Row

/// Compact project row for the menu bar popover.
private struct PopoverProjectRow: View {
    let project: ProjectConfig

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            Text(project.displayName)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

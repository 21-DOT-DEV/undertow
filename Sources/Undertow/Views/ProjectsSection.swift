import SwiftUI

/// Combined status and project management view.
struct ProjectsSection: View {
    var serviceStatus: ServiceStatus
    var setupManager: SetupManager

    @State private var showingAddSheet = false
    @State private var isRepairing = false
    @State private var repairMessage: String?

    private var allHealthy: Bool {
        serviceStatus.helperInstalled && serviceStatus.symlinkValid
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()

                if !allHealthy {
                    mcpServerGroup
                }

                projectsGroup
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Project", systemImage: "plus") {
                    showingAddSheet = true
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddProjectSheet(setupManager: setupManager) {
                serviceStatus.refreshAll(using: setupManager)
            }
        }
        .navigationTitle("Projects")
        .frame(minWidth: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "water.waves")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text("Undertow")
                    .font(.title.bold())
                Text(allHealthy ? "Ready" : "Setup required")
                    .font(.subheadline)
                    .foregroundColor(allHealthy ? .secondary : .orange)
            }
            Spacer()
            Button {
                serviceStatus.refreshAll(using: setupManager)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh status")
        }
    }

    // MARK: - MCP Server Status (shown only when unhealthy)

    private var mcpServerGroup: some View {
        GroupBox("MCP Server") {
            VStack(alignment: .leading, spacing: 8) {
                checkRow("MCP server installed", ok: serviceStatus.helperInstalled)
                checkRow("Shell path configured", ok: serviceStatus.symlinkValid)

                Divider()
                HStack {
                    if let message = repairMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Repair Installation") {
                        repairInstallation()
                    }
                    .disabled(isRepairing)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func checkRow(_ title: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .red)
            Text(title)
            Spacer()
        }
    }

    // MARK: - Projects

    private var projectsGroup: some View {
        Group {
            if serviceStatus.configuredProjects.isEmpty {
                ContentUnavailableView(
                    "No Projects Configured",
                    systemImage: "folder.badge.plus",
                    description: Text(
                        "Add a project to configure Undertow's MCP server."
                    )
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(serviceStatus.configuredProjects) { project in
                        ProjectRow(
                            project: project,
                            setupManager: setupManager
                        ) {
                            serviceStatus.refreshAll(using: setupManager)
                        }
                        if project.id != serviceStatus.configuredProjects.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func repairInstallation() {
        isRepairing = true
        defer { isRepairing = false }

        do {
            try setupManager.ensureHelperInstalled()
            repairMessage = "Installation repaired successfully."
            serviceStatus.refreshAll(using: setupManager)
        } catch {
            repairMessage = "Repair failed: \(error.localizedDescription)"
        }
    }
}

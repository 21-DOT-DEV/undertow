import SwiftUI
import UniformTypeIdentifiers
import UndertowKit

/// Sheet for selecting a project directory and configuring Undertow.
struct AddProjectSheet: View {
    let setupManager: SetupManager
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPath: String?
    @State private var configureForXcode = true
    @State private var configureForClaudeCode = true
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Project")
                .font(.title2.bold())

            Text("Select a project directory to configure Undertow's MCP server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Directory picker
            GroupBox {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(selectedPath ?? "No project selected")
                        .foregroundStyle(selectedPath == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        showingFilePicker = true
                    }
                }
            }

            // Config target toggles
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Xcode Coding Assistant", isOn: $configureForXcode)
                    Toggle("Claude Code CLI", isOn: $configureForClaudeCode)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Project") {
                    addProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    selectedPath == nil
                    || (!configureForXcode && !configureForClaudeCode)
                    || isAdding
                )
            }
        }
        .padding(20)
        .frame(width: 450)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedPath = url.path(percentEncoded: false)
            }
        }
    }

    private func addProject() {
        guard let path = selectedPath else { return }

        isAdding = true
        errorMessage = nil
        defer { isAdding = false }

        let target: ConfigTarget
        switch (configureForXcode, configureForClaudeCode) {
        case (true, true): target = .both
        case (true, false): target = .xcode
        case (false, true): target = .claudeCode
        case (false, false): return
        }

        do {
            try setupManager.addProject(path: path, target: target)
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

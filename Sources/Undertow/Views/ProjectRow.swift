import SwiftUI
import UndertowKit

/// A single project row showing configuration status and verification controls.
struct ProjectRow: View {
    let project: ProjectConfig
    let setupManager: SetupManager
    let onRemove: () -> Void

    @State private var verifyState: VerifyState = .idle

    enum VerifyState: Equatable {
        case idle
        case verifying
        case success(TimeInterval)
        case failed(String)

        var isVerifying: Bool {
            if case .verifying = self { return true }
            return false
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.headline)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    verifyBadge
                }
            }

            Spacer()

            Button {
                Task { await verify() }
            } label: {
                if verifyState.isVerifying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Verify")
                }
            }
            .disabled(verifyState.isVerifying)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Remove", role: .destructive) {
                try? setupManager.removeProject(path: project.path)
                onRemove()
            }
        }
    }

    @ViewBuilder
    private var verifyBadge: some View {
        switch verifyState {
        case .idle:
            EmptyView()
        case .verifying:
            EmptyView()
        case .success(let time):
            StatusBadge(
                text: String(format: "OK %.1fs", time),
                level: .success
            )
        case .failed(let message):
            StatusBadge(text: "Failed", level: .danger)
                .help(message)
        }
    }

    private func verify() async {
        verifyState = .verifying
        let manager = setupManager
        let path = project.path
        let result = await Task.detached {
            manager.verifyProject(path: path)
        }.value
        if result.success {
            verifyState = .success(result.responseTime ?? 0)
        } else {
            verifyState = .failed(result.message)
        }
    }
}

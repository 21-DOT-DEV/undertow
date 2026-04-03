import SwiftUI

/// A small capsule badge indicating status level.
struct StatusBadge: View {
    let text: String
    let level: Level

    enum Level {
        case info, success, warning, danger
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch level {
        case .info: .blue.opacity(0.15)
        case .success: .green.opacity(0.15)
        case .warning: .orange.opacity(0.15)
        case .danger: .red.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch level {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }
}

#Preview {
    HStack {
        StatusBadge(text: "Xcode", level: .info)
        StatusBadge(text: "Connected", level: .success)
        StatusBadge(text: "Missing", level: .warning)
        StatusBadge(text: "Error", level: .danger)
    }
    .padding()
}

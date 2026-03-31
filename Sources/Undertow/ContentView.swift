import SwiftUI

struct ContentView: View {
    var serviceStatus: ServiceStatus

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "water.waves")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Undertow")
                .font(.largeTitle.bold())

            Text("Xcode Coding Assistant Companion")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    StatusIndicator(connected: serviceStatus.bridgeConnected)
                    Text("Communication Bridge")
                }
                GridRow {
                    StatusIndicator(connected: serviceStatus.helperConnected)
                    Text("Background Agent")
                }
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }
}

private struct StatusIndicator: View {
    var connected: Bool

    var body: some View {
        Image(systemName: connected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(connected ? .green : .secondary)
    }
}

#Preview {
    ContentView(serviceStatus: ServiceStatus())
}

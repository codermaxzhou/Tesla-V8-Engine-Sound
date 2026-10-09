import SwiftUI

struct DriveHistoryView: View {
    let logger: DriveLogger
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent 10 seconds • 20 Hz").font(.caption).foregroundStyle(.secondary)
            graph("GPS speed", values: logger.latencyHistory.map { $0.gpsSpeed ?? .nan }, maximum: 250, color: .cyan, unit: "km/h")
            graph("Predicted speed", values: logger.latencyHistory.map(\.speed), maximum: 250, color: .blue, unit: "km/h")
            graph("Acceleration", values: logger.latencyHistory.map(\.acceleration), maximum: 8, color: .purple, unit: "m/s²", minimum: -8)
            graph("Throttle", values: logger.latencyHistory.map { $0.throttle * 100 }, maximum: 100, color: .orange, unit: "%")
            graph("RPM", values: logger.latencyHistory.map(\.rpm), maximum: 10000, color: .green, unit: "RPM")
        }
    }
    private func graph(_ title: String, values: [Double], maximum: Double, color: Color, unit: String, minimum: Double = 0) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(values.last.map { $0.isFinite ? String(format: "%.0f %@", $0, unit) : "—" } ?? "—").monospacedDigit()
            }.font(.caption)
            Canvas { context, size in
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height))
                context.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                var path = Path()
                var needsMove = true
                for (i, value) in values.enumerated() {
                    guard value.isFinite else { needsMove = true; continue }
                    let x = size.width * Double(i) / 199
                    let y = size.height * (1 - min(1, max(0, (value - minimum) / (maximum - minimum))))
                    if needsMove { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                    needsMove = false
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
            }.frame(height: 70)
                .accessibilityLabel("\(title) recent history")
        }
    }
}

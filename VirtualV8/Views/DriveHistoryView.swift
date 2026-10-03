import SwiftUI

struct DriveHistoryView: View {
    let logger: DriveLogger
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent 60 seconds • 5 Hz").font(.caption).foregroundStyle(.secondary)
            graph("Speed", values: logger.history.map(\.speed), maximum: 250, color: .blue, unit: "km/h")
            graph("Throttle", values: logger.history.map { $0.throttle * 100 }, maximum: 100, color: .orange, unit: "%")
            graph("RPM", values: logger.history.map(\.rpm), maximum: 6700, color: .green, unit: "RPM")
        }
    }
    private func graph(_ title: String, values: [Double], maximum: Double, color: Color, unit: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f %@", values.last ?? 0, unit)).monospacedDigit()
            }.font(.caption)
            Canvas { context, size in
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height))
                context.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                var path = Path()
                for (i, value) in values.enumerated() {
                    let x = size.width * Double(i) / 299
                    let y = size.height * (1 - min(1, max(0, value / maximum)))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
            }.frame(height: 70)
                .accessibilityLabel("\(title) recent history")
        }
    }
}

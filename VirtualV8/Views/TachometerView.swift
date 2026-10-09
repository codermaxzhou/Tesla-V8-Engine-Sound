import SwiftUI

struct TachometerView: View {
    let rpm: Double
    let normalizedRPM: Double
    let mode: EngineOperatingMode
    var profile: EngineProfile = .americanV8

    var body: some View {
        ZStack {
            Circle().trim(from: 0.12, to: 0.88)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle().trim(from: 0.12, to: 0.12 + 0.76 * normalizedRPM)
                .stroke(rpm >= profile.redlineRPM - 500 ? Color.red : Color.orange,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(90))
            VStack(spacing: 8) {
                Text(rpm, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                Text("RPM / \(Int(profile.redlineRPM).formatted())").font(.caption).foregroundStyle(.secondary)
                Text(mode.label).font(.headline).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: 320).frame(height: 280)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tachometer")
        .accessibilityValue("\(Int(rpm)) RPM, \(mode.label)")
    }
}

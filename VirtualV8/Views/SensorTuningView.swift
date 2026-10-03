import SwiftUI

struct SensorTuningView: View {
    @Bindable var sensors: SensorInputController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filter time constants • larger values smooth more").font(.caption).foregroundStyle(.secondary)
            control("Speed smoothing", value: $sensors.tuning.speedSmoothing, range: 0.1...2)
            control("Stopped duration", value: $sensors.tuning.stoppedDuration, range: 0.5...3)
            HStack {
                Text("Stopped threshold")
                Spacer()
                Text(String(format: "%.1f km/h", sensors.tuning.stoppedSpeedKmh)).monospacedDigit()
            }
            Slider(value: $sensors.tuning.stoppedSpeedKmh, in: 1...3)
            Button("Reset Sensor Tuning") { sensors.tuning = EstimatorTuning() }
        }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2f s", value.wrappedValue)).monospacedDigit() }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}

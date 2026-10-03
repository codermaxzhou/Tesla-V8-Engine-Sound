import SwiftUI

struct SimulationView: View {
    let controller: SimulationController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                DrivingDashboard(controller: controller)
                EngineControls(controller: controller)
                VStack(spacing: 20) {
                    input("Accelerator", value: controller.vehicle.estimatedThrottle,
                          range: 0...1, unit: "%", multiplier: 100, action: { controller.setThrottle($0) })
                    input("Brake", value: controller.vehicle.brakeInput,
                          range: 0...1, unit: "%", multiplier: 100, action: { controller.setBrake($0) })
                    input("Simulated vehicle speed", value: controller.vehicle.speedKmh,
                          range: 0...250, unit: "km/h", multiplier: 1, action: { controller.setSpeed($0) })
                }
                Button(controller.isDemoRunning ? (controller.activeScenario == nil ? "Cancel Automatic Demo" : "Cancel Scenario") : "Automatic Demo",
                       systemImage: controller.isDemoRunning ? "stop.circle" : "play.circle") {
                    if controller.isDemoRunning { controller.cancelDemo() }
                    else { controller.startDemo() }
                }.buttonStyle(.borderedProminent)
                if controller.isDemoRunning {
                    ProgressView(value: controller.demoElapsed, total: controller.scenarioDuration)
                }
                ScenarioControlsView(controller: controller)
                NavigationLink("Developer / Calibration") { DeveloperView(controller: controller) }
                AudioTuningView(audio: controller.audio)
                Text(controller.demoStage).font(.subheadline).foregroundStyle(.secondary)
                Text("Speed is manually controlled. The demo drives all inputs automatically; moving any slider returns to manual control.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }
        .onAppear { controller.selectInputMode(.simulation) }
        .navigationTitle("Simulation Mode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func input(_ title: String, value: Double, range: ClosedRange<Double>,
                       unit: String, multiplier: Double, action: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * multiplier)) \(unit)").monospacedDigit().foregroundStyle(.orange)
            }
            Slider(value: Binding(get: { value }, set: action), in: range)
                .accessibilityLabel(title)
        }
    }
}

import SwiftUI

struct ScenarioControlsView: View {
    let controller: SimulationController
    @State private var selected = SimulationScenario.city
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repeatable Test Scenarios").font(.headline)
            Picker("Scenario", selection: $selected) {
                ForEach(SimulationScenario.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Run Scenario", systemImage: "play.circle") { controller.startScenario(selected) }
                .buttonStyle(.bordered)
            Text("Inputs repeat exactly with the current calibration and driving mode. A scenario restarts the engine and keeps logging active.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

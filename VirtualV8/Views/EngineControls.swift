import SwiftUI

struct EngineControls: View {
    let controller: SimulationController

    var body: some View {
        HStack {
            Button("START ENGINE") { controller.startEngine() }
                .disabled(controller.engine.isRunning)
            Button("STOP ENGINE", role: .destructive) { controller.stopEngine() }
                .disabled(!controller.engine.isRunning)
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
    }
}

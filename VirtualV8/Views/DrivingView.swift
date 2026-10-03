import SwiftUI

struct DrivingView: View {
    let controller: SimulationController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                DrivingDashboard(controller: controller)
                if controller.inputMode == .realDrive {
                    Text("Configure engine parameters while parked.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if controller.canCalibrate {
                    NavigationLink("Developer / Calibration") { DeveloperView(controller: controller) }
                    if controller.inputMode == .simulation {
                        NavigationLink("Open Simulation Controls") { SimulationView(controller: controller) }
                    }
                }
            }.padding()
        }
        .navigationTitle("Driving")
        .navigationBarTitleDisplayMode(.inline)
    }
}

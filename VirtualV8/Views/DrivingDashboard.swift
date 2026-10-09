import SwiftUI

struct DrivingDashboard: View {
    let controller: SimulationController

    var body: some View {
        VStack(spacing: 16) {
            TachometerView(rpm: controller.engine.rpm,
                           normalizedRPM: controller.engine.normalizedRPM,
                           mode: controller.operatingMode, profile: controller.profile)
            HStack(spacing: 20) {
                metric("km/h", value: String(format: "%.0f", controller.vehicle.speedKmh))
                metric("Gear", value: "\(controller.transmission.currentGear)")
                metric("Estimated Throttle", value: "\(Int(controller.vehicle.estimatedThrottle * 100))%")
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack {
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

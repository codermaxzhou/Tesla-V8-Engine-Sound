import SwiftUI

struct MainView: View {
    @Bindable var controller: SimulationController

    var body: some View {
        NavigationStack {
            Form {
                Section("Engine Profile") {
                    Label(controller.profile.name, systemImage: "engine.combustion")
                }
                Section("Input Mode") {
                    Picker("Input Mode", selection: Binding(get: { controller.inputMode }, set: { controller.selectInputMode($0) })) {
                        ForEach(ApplicationInputMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented).disabled(!controller.canCalibrate)
                }
                if controller.inputMode == .realDrive {
                    Section("Real Drive") {
                        Text("Configure engine parameters while parked.")
                        SensorStatusView(controller: controller).disabled(!controller.canCalibrate)
                    }
                }
                Section("Driving Mode") {
                    if controller.inputMode == .simulation {
                        Picker("Driving Mode", selection: $controller.drivingMode) {
                            ForEach(DrivingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }.pickerStyle(.segmented)
                    } else { Text(controller.drivingMode.rawValue) }
                }
                Section {
                    if controller.engine.isRunning {
                        Button("Stop Engine", systemImage: "power") { controller.stopEngine() }
                    } else {
                        Button("Start Engine", systemImage: "power") { controller.startEngine() }
                    }
                    NavigationLink("Driving Screen") { DrivingView(controller: controller) }
                    NavigationLink("Simulation Mode") { SimulationView(controller: controller) }.disabled(!controller.canCalibrate)
                    NavigationLink("Developer / Calibration") { DeveloperView(controller: controller) }.disabled(!controller.canCalibrate)
                    NavigationLink("Diagnostics") { DiagnosticsView(controller: controller) }.disabled(!controller.canCalibrate)
                }
                Section {
                    LabeledContent("Engine", value: controller.operatingMode.label)
                    Text("MVP • Simulation & Real Drive • Hybrid V8 audio")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Virtual V8")
        }
    }
}

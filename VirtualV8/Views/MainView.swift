import SwiftUI

struct MainView: View {
    @Bindable var controller: SimulationController

    var body: some View {
        NavigationStack {
            Form {
                Section("Engine Profile") {
                    NavigationLink {
                        EngineProfileSelectionView(controller: controller)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.profile.name).foregroundStyle(.primary)
                            Text("Choose engine profile").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!controller.canCalibrate)
                    .accessibilityIdentifier("engine-profile-selector")
                    if !controller.canCalibrate { Text("Configure engine parameters while parked.").font(.caption).foregroundStyle(.secondary) }
                    if let description = controller.profile.soundDescription { Text(description).font(.caption).foregroundStyle(.secondary) }
                    if controller.profile == .amgGTR { Text("AMG GT R-inspired audio recreation").font(.caption).foregroundStyle(.secondary) }
                    if controller.profile == .supra2JZ { Text("2JZ-inspired recreation · Intake volume controls turbo whistle and release").font(.caption).foregroundStyle(.secondary) }
                    if controller.profile == .bmwS65 { Text("S65-inspired audio recreation").font(.caption).foregroundStyle(.secondary) }
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

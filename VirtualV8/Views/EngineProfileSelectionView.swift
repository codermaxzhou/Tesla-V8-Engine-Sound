import SwiftUI

/// Explicit rows avoid opaque Picker tags and keep selection identity independent of profile metadata.
struct EngineProfileSelectionView: View {
    let controller: SimulationController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(EngineProfile.available) { profile in
                    Button {
                        if controller.selectProfile(id: profile.id) { dismiss() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name).foregroundStyle(.primary)
                                if let description = profile.soundDescription {
                                    Text(description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if controller.profile.id == profile.id {
                                Image(systemName: "checkmark").foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.engine.isRunning || !controller.canCalibrate)
                    .accessibilityIdentifier("engine-profile-" + profile.id)
                    .accessibilityValue(controller.profile.id == profile.id ? "Selected" : "")
                }
            } footer: {
                Text("Profile selection is saved automatically.")
            }
            if controller.engine.isRunning {
                Section {
                    Text("Stop the engine to change profile.")
                    Button("Stop Engine", systemImage: "power") { controller.stopEngine() }
                        .accessibilityIdentifier("profile-stop-engine")
                }
            }
            if !controller.canCalibrate {
                Section { Text("Configure engine parameters while parked.") }
            }
        }
        .navigationTitle("Engine Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import UIKit

@main
struct VirtualV8App: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var simulation = SimulationController(settingsDefaults: .standard)

    var body: some Scene {
        WindowGroup {
            MainView(controller: simulation)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onChange(of: scenePhase == .active && simulation.shouldKeepScreenAwake, initial: true) { _, keepAwake in
                    UIApplication.shared.isIdleTimerDisabled = keepAwake
                }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { simulation.setForeground(false) }
            else if phase == .active { simulation.setForeground(true) }
        }
    }
}

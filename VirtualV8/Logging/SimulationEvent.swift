import Foundation

struct SimulationEvent: Identifiable {
    let id = UUID()
    let message: String
    var timestamp = Date()
}

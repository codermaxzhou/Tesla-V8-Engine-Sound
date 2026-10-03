enum DrivingMode: String, CaseIterable, Identifiable, Codable {
    case comfort = "Comfort"
    case sport = "Sport"
    case track = "Track"

    var id: String { rawValue }
    // Engine pedal response; shift thresholds are owned by VirtualTransmission.
    var response: Double {
        switch self {
        case .comfort: return 0.85
        case .sport: return 1
        case .track: return 1.15
        }
    }
}

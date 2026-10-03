import Foundation

struct EngineState {
    var rpm: Double = 0
    var targetRPM: Double = 0
    var normalizedRPM: Double = 0
    var load: Double = 0
    var throttle: Double = 0
    var isRunning = false
    var isOnLimiter = false
}

enum EngineOperatingMode: String, CaseIterable {
    case off, starting, idle, cruise, acceleration, fullLoad, overrun, shift, revMatch, limiter

    var label: String {
        switch self {
        case .fullLoad: return "Full Load"
        case .revMatch: return "Rev Match"
        default: return rawValue.capitalized
        }
    }
}

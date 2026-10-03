import Foundation

struct DemoFrame {
    let speed: Double
    let throttle: Double
    let brake: Double
    let label: String
}

/// A deterministic 42-second indoor demonstration, independent of SwiftUI.
enum DemoSequence {
    static let duration: Double = 42

    static func frame(at time: Double) -> DemoFrame {
        switch time {
        case ..<0.8: return DemoFrame(speed: 0, throttle: 0, brake: 0, label: "Starting engine")
        case ..<3: return DemoFrame(speed: 0, throttle: 0, brake: 0, label: "Idle")
        case ..<23:
            return DemoFrame(speed: (time - 3) / 20 * 160, throttle: 0.98, brake: 0, label: "First gear / acceleration / upshifts")
        case ..<26: return DemoFrame(speed: 160, throttle: 0.98, brake: 0, label: "High RPM operation")
        case ..<30:
            return DemoFrame(speed: 160 - (time - 26) * 5, throttle: 0, brake: 0, label: "Throttle lift / overrun")
        case ..<37:
            return DemoFrame(speed: max(0, 140 * (1 - (time - 30) / 7)), throttle: 0, brake: 0.7, label: "Braking / rev matching / downshifts")
        default: return DemoFrame(speed: 0, throttle: 0, brake: 0, label: "Stopped / returning to idle")
        }
    }
}

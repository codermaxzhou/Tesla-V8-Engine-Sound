import Foundation

enum SimulationScenario: String, CaseIterable, Identifiable {
    case city = "City Driving"
    case fullThrottle = "Full Throttle Acceleration"
    case highway = "Highway Cruise"
    case liftDownshift = "Lift-Off and Downshift"
    case stopAndGo = "Stop-and-Go"
    case aggressiveSport = "Aggressive Sport Drive"
    var id: String { rawValue }
    var duration: Double { points.last!.time }

    struct Point {
        let time: Double
        let speed: Double
        let throttle: Double
        let brake: Double
        let label: String
    }
    // Speeds interpolate continuously. Pedal changes occur exactly at each point's time.
    // These fixtures never change calibration/driving mode, so A/B comparisons stay valid.
    private var points: [Point] {
        func p(_ time: Double, _ speed: Double, _ throttle: Double, _ label: String, _ brake: Double = 0) -> Point {
            Point(time: time, speed: speed, throttle: throttle, brake: brake, label: label)
        }
        switch self {
        case .city:
            return [p(0,0,0,"Idle"),p(3,0,0.4,"City acceleration"),p(11,50,0.18,"City cruise"),
                    p(18,50,0,"Braking",0.45),p(25,0,0,"Stopped"),p(28,0,0.35,"City acceleration"),
                    p(35,40,0,"Braking",0.5),p(42,0,0,"Idle"),p(58,0,0,"Complete")]
        case .fullThrottle:
            return [p(0,0,0,"Idle"),p(3,0,1,"Full throttle / upshifts"),p(25,180,1,"High RPM"),
                    p(28,180,0,"Lift / overrun"),p(32,160,0,"Downshifts",0.7),
                    p(44,0,0,"Idle"),p(60,0,0,"Complete")]
        case .highway:
            return [p(0,0,0,"Idle"),p(3,0,0.6,"On-ramp acceleration"),p(25,110,0.18,"Highway cruise"),
                    p(43,110,0.35,"Gentle acceleration"),p(49,120,0.12,"Highway cruise"),
                    p(59,120,0,"Exit / downshifts",0.35),p(77,0,0,"Idle"),p(93,0,0,"Complete")]
        case .liftDownshift:
            return [p(0,0,0,"Idle"),p(3,0,0.95,"Acceleration / upshifts"),p(23,140,0.95,"High load"),
                    p(26,140,0,"Aggressive lift / overrun"),p(30,120,0,"Braking / rev matching",0.8),
                    p(41,0,0,"Idle"),p(57,0,0,"Complete")]
        case .stopAndGo:
            return [p(0,0,0,"Idle"),p(3,0,0.35,"Pull away"),p(8,25,0,"Stop",0.5),p(13,0,0,"Wait"),
                    p(16,0,0.45,"Pull away"),p(22,35,0,"Stop",0.6),p(28,0,0,"Wait"),
                    p(31,0,0.3,"Pull away"),p(36,20,0,"Stop",0.4),p(41,0,0,"Idle"),p(57,0,0,"Complete")]
        case .aggressiveSport:
            return [p(0,0,0,"Idle"),p(3,0,1,"Hard acceleration"),p(20,140,0,"Lift / overrun"),
                    p(23,125,0,"Brake / downshift",0.65),p(28,75,1,"Kickdown / acceleration"),
                    p(36,155,0,"Aggressive lift"),p(39,140,0,"Hard braking / rev matching",0.9),
                    p(51,0,0,"Idle"),p(67,0,0,"Complete")]
        }
    }
    func frame(at time: Double) -> DemoFrame {
        let points = points
        let time = time.isFinite ? max(0, min(duration, time)) : 0
        guard let index = points.indices.last(where: { points[$0].time <= time }), index < points.count - 1 else {
            return DemoFrame(speed: 0, throttle: 0, brake: 0, label: "Complete — engine idling")
        }
        let a = points[index], b = points[index + 1]
        let fraction = (time - a.time) / (b.time - a.time)
        return DemoFrame(speed: a.speed + (b.speed - a.speed) * fraction,
                         throttle: a.throttle, brake: a.brake, label: a.label)
    }
}

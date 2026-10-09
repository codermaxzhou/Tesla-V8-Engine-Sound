import Foundation

enum AudioLayer: String, CaseIterable, Identifiable {
    case idle, lowRPM, midRPM, highRPM, highLoad, intake, overrun
    case shiftTransient, revMatch, backfire, limiter, turboSpool, pressureRelease
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lowRPM: return "lowGain"
        case .midRPM: return "midGain"
        case .highRPM: return "highGain"
        case .highLoad: return "loadGain"
        default: return rawValue + "Gain"
        }
    }
}

struct AudioTuning: Codable, Equatable {
    var masterVolume = 0.45
    var engineVolume = 1.0
    var intakeVolume = 0.5
    var exhaustVolume = 0.8
    var backfireAmount = 0.5
    var shiftTransientVolume = 0.7
    var isMuted = false
    var audioLatencyCompensationMs = 0.0

    private enum CodingKeys: String, CodingKey {
        case masterVolume, engineVolume, intakeVolume, exhaustVolume, backfireAmount
        case shiftTransientVolume, isMuted, audioLatencyCompensationMs
    }
    init() { }
    // Older Phase 5 calibration files have no latency field; preserve every saved value.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        masterVolume = try values.decodeIfPresent(Double.self, forKey: .masterVolume) ?? 0.45
        engineVolume = try values.decodeIfPresent(Double.self, forKey: .engineVolume) ?? 1
        intakeVolume = try values.decodeIfPresent(Double.self, forKey: .intakeVolume) ?? 0.5
        exhaustVolume = try values.decodeIfPresent(Double.self, forKey: .exhaustVolume) ?? 0.8
        backfireAmount = try values.decodeIfPresent(Double.self, forKey: .backfireAmount) ?? 0.5
        shiftTransientVolume = try values.decodeIfPresent(Double.self, forKey: .shiftTransientVolume) ?? 0.7
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        audioLatencyCompensationMs = try values.decodeIfPresent(Double.self, forKey: .audioLatencyCompensationMs) ?? 0
    }
    static func bounded(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

struct AudioEvent {
    let layer: AudioLayer
    let asset: String
    let gain: Double
}

/// Pure control-rate mixer. This model never changes the virtual drivetrain.
struct AudioMixModel {
    private(set) var gains: [AudioLayer: Double] = [:]
    private var previousThrottle = 0.0
    private var wasShifting = false
    private var backfireClock = 100.0
    private var downshiftBurstClock = 100.0
    private var limiterClock = 0.0
    private var pendingPops: [Double] = []
    private var shiftVariant = 0
    private(set) var turboPressure = 0.0
    private var releaseArmed = false
    private var releaseClock = 100.0
    let profile: EngineProfile
    private var randomState: UInt64

    // Fresh entropy in the app; an explicit seed makes audio regressions reproducible.
    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max), profile: EngineProfile = .americanV8) {
        self.profile = profile
        randomState = seed
    }

    static func rpmWeights(_ rpm: Double) -> [AudioLayer: Double] {
        let r = rpm.isFinite ? rpm : 750
        func ramp(_ a: Double, _ b: Double) -> Double {
            let t = min(1, max(0, (r - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        let weights: [AudioLayer: Double] = [
            .idle: 1 - ramp(1000, 1200),
            .lowRPM: ramp(1000, 1200) * (1 - ramp(2500, 3000)),
            .midRPM: ramp(2500, 3000) * (1 - ramp(4500, 5000)),
            .highRPM: ramp(4500, 5000)
        ]
        let sum = max(0.001, weights.values.reduce(0, +))
        return weights.mapValues { $0 / sum }
    }

    mutating func update(engine: EngineState, vehicle: VehicleState, transmission: TransmissionState,
                         mode: EngineOperatingMode, drivingMode: DrivingMode,
                         tuning: AudioTuning, deltaTime: Double, audioRPM: Double? = nil) -> [AudioEvent] {
        guard deltaTime.isFinite, deltaTime > 0 else { return [] }
        backfireClock += deltaTime
        downshiftBurstClock += deltaTime
        limiterClock += deltaTime
        releaseClock += deltaTime
        let candidateRPM = audioRPM ?? engine.rpm
        let rpm = candidateRPM.isFinite ? max(0, candidateRPM) : 750
        let master = tuning.isMuted ? 0 : AudioTuning.bounded(tuning.masterVolume)
        let engineLevel = master * AudioTuning.bounded(tuning.engineVolume)
        let exhaust = engineLevel * AudioTuning.bounded(tuning.exhaustVolume)
        let throttle = AudioTuning.bounded(vehicle.estimatedThrottle)
        // Perceptual attack bypasses slow drivetrain load convergence. It uses the common
        // vehicle state, so neither the mixer nor engine needs to know the input source.
        let audioThrottle = mode == .overrun ? 0 : throttle
        let attack = audioThrottle > 0.05 && vehicle.accelerationMs2 > 0.4
            ? min(0.10, max(0, vehicle.jerkMs3) / 80) : 0
        let load = max(AudioTuning.bounded(engine.load), min(1, audioThrottle * 0.7 + attack))
        let intake = engineLevel * AudioTuning.bounded(tuning.intakeVolume)
        let storedPressure = turboPressure
        let rpmFactor = min(1, max(0, (engine.rpm - 1500) / 2500))
        let pressureTarget = profile.hasTurbo && engine.isRunning ? throttle * load * rpmFactor : 0
        turboPressure += (pressureTarget - turboPressure) * (1 - exp(-(pressureTarget > turboPressure ? 1.8 : 5.5) * deltaTime))
        if profile.hasTurbo, throttle > 0.45, turboPressure > 0.18 { releaseArmed = true }
        let newUpshift = transmission.isShifting && !wasShifting && transmission.shiftType == .upshift
        let shouldRelease = profile.hasTurbo && engine.isRunning && storedPressure > 0.12 && releaseClock >= 0.45
            && ((releaseArmed && (throttle < 0.2 || vehicle.didDetectThrottleLift)) || newUpshift)
        let duck = transmission.isShifting && transmission.shiftType == .upshift ? 0.3 : 1
        var targets = Self.rpmWeights(rpm / profile.redlineScale).mapValues { $0 * exhaust * (0.4 + load * 0.6) }
        targets[.highLoad] = exhaust * load * duck * 0.65
        targets[.intake] = engineLevel * AudioTuning.bounded(tuning.intakeVolume) * audioThrottle * 0.5
        let overrun = mode == .overrun || (mode == .idle && throttle < 0.15 && rpm > 1200)
        targets[.overrun] = overrun ? exhaust * min(1, rpm / 4000) * 0.65 : 0
        targets[.shiftTransient] = engineLevel * AudioTuning.bounded(tuning.shiftTransientVolume)
        targets[.revMatch] = targets[.shiftTransient]
        targets[.backfire] = min(1, exhaust * AudioTuning.bounded(tuning.backfireAmount) * 2)
        targets[.limiter] = exhaust * 0.5
        targets[.turboSpool] = profile.hasTurbo ? intake * turboPressure * 0.8 : 0
        targets[.pressureRelease] = profile.hasTurbo ? intake : 0
        for layer in AudioLayer.allCases {
            let target = engine.isRunning ? targets[layer, default: 0] : 0
            let fastAttack = (layer == .highLoad || layer == .intake) && target > gains[layer, default: 0]
            gains[layer, default: 0] += (target - gains[layer, default: 0]) * (1 - exp(-(fastAttack ? 35 : 12) * deltaTime))
        }
        var events: [AudioEvent] = []
        if engine.isRunning {
            if shouldRelease {
                releaseClock = 0
                releaseArmed = false
                turboPressure *= 0.25
                if !tuning.isMuted && intake > 0.0001 {
                    events.append(AudioEvent(layer: .pressureRelease,
                        asset: "pressure_release_\(1 + Int(random() * 2))",
                        gain: gains[.pressureRelease, default: 0] * (0.55 + 0.45 * storedPressure)))
                }
            }
            let amount = AudioTuning.bounded(tuning.backfireAmount)
            let backfire = BackfireController(configuration: .forMode(drivingMode))
            var downshiftCount = 0
            if transmission.isShifting && !wasShifting {
                if transmission.shiftType == .upshift {
                    shiftVariant = shiftVariant % 2 + 1
                    events.append(AudioEvent(layer: .shiftTransient, asset: "shift_up_\(shiftVariant)",
                                             gain: gains[.shiftTransient, default: 0]))
                } else if transmission.shiftType == .downshift {
                    downshiftCount = backfire.downshiftBurstCount(rpm: max(engine.rpm, engine.targetRPM),
                        timeSinceLastBurst: downshiftBurstClock, amount: amount, roll: random(), burstRoll: random())
                    events.append(AudioEvent(layer: .revMatch, asset: "downshift",
                                             gain: gains[.revMatch, default: 0]))
                }
            }
            let liftCount = backfire.burstCount(
                currentThrottle: vehicle.didDetectThrottleLift ? 0 : throttle,
                previousThrottle: previousThrottle, rpm: engine.rpm,
                engineMode: mode, deceleration: vehicle.accelerationMs2,
                timeSinceLastBackfire: backfireClock,
                amount: amount, roll: random(), burstRoll: random())
            if amount == 0 || tuning.isMuted { pendingPops.removeAll() }
            else if downshiftCount > 0 || (liftCount > 0 && pendingPops.isEmpty) {
                let isDownshift = downshiftCount > 0
                let count = isDownshift ? downshiftCount : liftCount
                backfireClock = 0
                if isDownshift { downshiftBurstClock = 0 }
                // Follow the blip with irregular pops; replace rather than stack bursts.
                var delay = isDownshift ? 0.06 + random() * 0.08 : 0
                pendingPops = [delay]
                for _ in 1..<count {
                    delay += isDownshift ? 0.07 + pow(random(), 1.2) * 0.13 : 0.12 + random() * 0.19
                    pendingPops.append(delay)
                }
            }
            for index in pendingPops.indices { pendingPops[index] -= deltaTime }
            while let next = pendingPops.first, next <= 0 {
                pendingPops.removeFirst()
                events.append(AudioEvent(layer: .backfire, asset: "pop_\(1 + Int(random() * 3))",
                                         gain: gains[.backfire, default: 0]))
            }
            if engine.isOnLimiter || engine.rpm >= profile.hardLimiterRPM - 150 {
                if limiterClock >= 0.13 + random() * 0.09 {
                    limiterClock = 0
                    events.append(AudioEvent(layer: .limiter, asset: "limiter", gain: gains[.limiter, default: 0]))
                }
            } else { limiterClock = 0 }
        } else {
            pendingPops.removeAll()
            previousThrottle = 0
            backfireClock = 100
            downshiftBurstClock = 100
            turboPressure = 0
            releaseArmed = false
            releaseClock = 100
        }
        previousThrottle = engine.isRunning ? throttle : 0
        wasShifting = engine.isRunning && transmission.isShifting
        return events
    }

    private mutating func random() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / 9007199254740992.0
    }
}

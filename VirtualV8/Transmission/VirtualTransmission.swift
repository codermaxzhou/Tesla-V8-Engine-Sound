import Foundation

struct VirtualTransmission {
    var tuning = TransmissionTuning()
    static let gearRatios = [4.56, 2.97, 2.08, 1.69, 1.27, 1.00, 0.85, 0.65]
    let finalDrive: Double
    let tireCircumference: Double
    private(set) var state = TransmissionState()
    private(set) var shiftDuration = 0.3
    private(set) var shiftStartRPM = 750.0
    private(set) var shiftStartSpeed = 0.0
    private(set) var isRevMatching = false
    private var timeInGear = 0.0
    private var cooldown = 0.0
    private var sinceLastShift = 10.0
    private var lastShiftType: ShiftType = .none
    private var previousThrottle = 0.0
    private var kickdownRequested = false

    init(finalDrive: Double = 3.55, tireCircumference: Double = 2.10) {
        precondition(finalDrive.isFinite && finalDrive > 0)
        precondition(tireCircumference.isFinite && tireCircumference > 0)
        self.finalDrive = finalDrive
        self.tireCircumference = tireCircumference
    }

    func ratio(for gear: Int) -> Double {
        Self.gearRatios[min(8, max(1, gear)) - 1]
    }

    func rpm(forSpeedKmh speed: Double, gear: Int) -> Double {
        guard speed.isFinite else { return 0 }
        return max(0, speed) / 3.6 / tireCircumference * 60 * ratio(for: gear) * finalDrive
    }

    mutating func reset() {
        let savedTuning = tuning
        self = VirtualTransmission(finalDrive: finalDrive, tireCircumference: tireCircumference)
        tuning = savedTuning
    }

    func upshiftRPM(throttle: Double, mode: DrivingMode) -> Double {
        let t = min(1, max(0, throttle))
        let base: Double
        switch mode {
        case .comfort: base = 2200 + 800 * t + 3000 * pow(t, 3)
        case .sport: base = 3500 + 1500 * t
        case .track: base = 4200 + 2150 * t
        }
        return base * tuning.upshiftAggressiveness
    }

    mutating func update(deltaTime: Double, vehicle: VehicleState,
                         engine: EngineState, mode: DrivingMode, configuration: EngineProfile) {
        guard deltaTime.isFinite, deltaTime > 0, engine.isRunning else { return }
        sinceLastShift += deltaTime
        cooldown = max(0, cooldown - deltaTime)
        let throttle = vehicle.estimatedThrottle
        let throttleRise = throttle - previousThrottle
        previousThrottle = throttle
        if throttle < 0.75 { kickdownRequested = false }
        else if throttleRise >= 0.2 { kickdownRequested = true }
        if state.isShifting {
            state.shiftProgress = min(1, state.shiftProgress + deltaTime / shiftDuration)
            if state.shiftProgress >= 1 - 1e-9 {
                state.currentGear = state.targetGear
                state.isShifting = false
                state.shiftType = .none
                isRevMatching = false
                timeInGear = 0
                cooldown = 0.65
                sinceLastShift = 0
            }
            return
        }
        timeInGear += deltaTime
        let minimumTime = mode == .comfort ? 1.0 : mode == .sport ? 0.8 : 0.6
        guard cooldown == 0, timeInGear >= minimumTime else { return }
        let gear = state.currentGear
        let speed = vehicle.speedKmh
        // Always shift before the soft limiter's cut can hold RPM below the strategy threshold.
        let upRPM = min(configuration.softLimiterRPM - 100,
                        upshiftRPM(throttle: throttle, mode: mode) * configuration.redlineScale)
        let wheelRPM = rpm(forSpeedKmh: speed, gear: gear)
        let downRPM = (mode == .comfort ? 1100 + 400 * throttle
            : mode == .sport ? 1500 + 500 * throttle : 2000 + 600 * throttle) * tuning.downshiftAggressiveness

        // A sustained high pedal at low RPM may kick down after cooldown as well.
        if gear > 1, speed > 12, throttle >= 0.75,
           kickdownRequested || engine.rpm < 2000 * tuning.downshiftAggressiveness {
            for candidate in 1..<gear {
                let predicted = rpm(forSpeedKmh: speed, gear: candidate)
                if predicted > wheelRPM * 1.2,
                   predicted < min(configuration.redlineRPM - 200, upRPM - 400),
                   canShift(.downshift, speed: speed) {
                    beginShift(to: candidate, vehicle: vehicle, engine: engine, mode: mode)
                    kickdownRequested = false
                    return
                }
            }
        }
        let nextRPM = rpm(forSpeedKmh: speed, gear: gear + 1)
        let minimumAfterUpshift = mode == .comfort ? 1150.0 : mode == .sport ? 1650 : 2250
        if gear < 8, speed > 12, engine.rpm >= upRPM, wheelRPM >= upRPM * 0.8,
           nextRPM >= minimumAfterUpshift, canShift(.upshift, speed: speed) {
            beginShift(to: gear + 1, vehicle: vehicle, engine: engine, mode: mode)
        } else if gear > 1, wheelRPM < downRPM || speed < 8 {
            let lowerRPM = rpm(forSpeedKmh: speed, gear: gear - 1)
            // Separate up/down thresholds prevent bouncing across the same boundary.
            if lowerRPM < min(configuration.redlineRPM - 200, upRPM - 350),
               canShift(.downshift, speed: speed) {
                beginShift(to: gear - 1, vehicle: vehicle, engine: engine, mode: mode)
            }
        }
    }

    private func canShift(_ type: ShiftType, speed: Double) -> Bool {
        type == lastShiftType || lastShiftType == .none || sinceLastShift >= 2 || speed < 8
    }

    private mutating func beginShift(to gear: Int, vehicle: VehicleState,
                                    engine: EngineState, mode: DrivingMode) {
        state.targetGear = min(8, max(1, gear))
        state.shiftType = gear > state.currentGear ? .upshift : .downshift
        lastShiftType = state.shiftType
        state.isShifting = true
        state.shiftProgress = 0
        shiftDuration = mode == .comfort ? 0.45 - vehicle.estimatedThrottle * 0.12
            : mode == .sport ? 0.30 - vehicle.estimatedThrottle * 0.10
            : 0.22 - vehicle.estimatedThrottle * 0.07
        shiftDuration = min(0.65, max(0.15, shiftDuration * tuning.shiftDuration))
        shiftStartRPM = engine.rpm
        shiftStartSpeed = vehicle.speedKmh
        isRevMatching = state.shiftType == .downshift
            && (mode != .comfort || vehicle.estimatedThrottle >= 0.65 || vehicle.brakeInput >= 0.4)
    }
}

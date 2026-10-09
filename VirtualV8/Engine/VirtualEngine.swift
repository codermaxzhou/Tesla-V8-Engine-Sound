import Foundation

/// A deliberately simplified virtual engine, without audio or sensor input.
struct VirtualEngine {
    var tuning = EngineTuning()
    let configuration: EngineProfile
    private(set) var state = EngineState()
    private(set) var operatingMode: EngineOperatingMode = .off
    private var startupElapsed = 0.0
    private var throttleTransient = 0.0
    private var previousThrottle = 0.0
    private var lifting = false

    init(configuration: EngineProfile = .americanV8) {
        self.configuration = configuration
    }

    mutating func start() {
        guard !state.isRunning else { return }
        state.isRunning = true
        // Starting establishes combustion at idle; all subsequent RPM changes are smoothed.
        state.rpm = configuration.idleRPM
        state.targetRPM = configuration.idleRPM
        state.normalizedRPM = state.rpm / configuration.redlineRPM
        startupElapsed = 0
        throttleTransient = 0; previousThrottle = 0; lifting = false
        operatingMode = .starting
    }

    mutating func stop() {
        state = EngineState()
        operatingMode = .off
        startupElapsed = 0
        throttleTransient = 0; previousThrottle = 0; lifting = false
    }

    mutating func update(deltaTime: Double, vehicle: VehicleState,
                         transmission: VirtualTransmission, drivingMode: DrivingMode) {
        guard state.isRunning, deltaTime.isFinite, deltaTime > 0 else { return }
        startupElapsed += deltaTime
        if vehicle.didDetectThrottleLift { lifting = true }
        if vehicle.rawEstimatedThrottle > 0.05 || vehicle.estimatedThrottle < 0.02 { lifting = false }
        let throttle = lifting ? 0 : min(1, max(0, vehicle.estimatedThrottle))
        if lifting { throttleTransient = 0 }
        // Pedal attack adds bounded converter flare immediately, independent of GPS speed.
        throttleTransient = min(450, throttleTransient + max(0, throttle - previousThrottle) * 450)
        throttleTransient *= exp(-deltaTime / 0.35)
        previousThrottle = throttle
        state.throttle = approach(state.throttle, throttle, rate: 9 * drivingMode.response, dt: deltaTime)
        let load = state.throttle * (0.35 + min(1, vehicle.speedKmh / 30) * 0.65)
            * (1 - vehicle.brakeInput * 0.25)
        state.load = approach(state.load, load, rate: 6, dt: deltaTime)

        let wheelRPM = transmission.rpm(forSpeedKmh: vehicle.speedKmh,
                                        gear: transmission.state.currentGear)
        var requestedRPM: Double
        var rate: Double
        if startupElapsed < 0.8 {
            // Brief start flare, then settle to idle without falling below idle.
            requestedRPM = configuration.idleRPM + 400 * sin(startupElapsed / 0.8 * .pi)
            rate = 8
            operatingMode = .starting
        } else if transmission.state.isShifting {
            let fromRatio = transmission.ratio(for: transmission.state.currentGear)
            let toRatio = transmission.ratio(for: transmission.state.targetGear)
            let speedChangeRPM = transmission.rpm(forSpeedKmh: vehicle.speedKmh,
                                                  gear: transmission.state.targetGear)
                - transmission.rpm(forSpeedKmh: transmission.shiftStartSpeed,
                                   gear: transmission.state.targetGear)
            requestedRPM = transmission.shiftStartRPM * toRatio / fromRatio + speedChangeRPM
            rate = transmission.isRevMatching ? 18 * transmission.tuning.downshiftAggressiveness : 14
            operatingMode = transmission.isRevMatching ? .revMatch : .shift
        } else {
            // The torque converter slips near rest. At road speed the driveline determines RPM.
            let coupling = min(1, max(0, vehicle.speedKmh / 12))
            let freeRPM = configuration.idleRPM + state.throttle
                * (configuration.hardLimiterRPM - configuration.idleRPM)
            let slipRPM = state.throttle * max(0, 1 - vehicle.speedKmh / 30) * 650
            requestedRPM = freeRPM * (1 - coupling)
                + max(configuration.idleRPM, wheelRPM + slipRPM) * coupling
                + throttleTransient * coupling
            if vehicle.isStopped && throttle < 0.02 {
                rate = 3.5
                operatingMode = .idle
            } else if throttle < 0.02 {
                rate = 2.6
                operatingMode = .overrun
            } else {
                rate = requestedRPM > state.rpm ? 3.2 * drivingMode.response : 2.2
                operatingMode = throttle >= 0.8 ? .fullLoad
                    : vehicle.isAccelerating || throttle > 0.35 ? .acceleration : .cruise
            }
        }

        // Soft limiting reduces the target; the hard limit is an unconditional safety bound.
        state.isOnLimiter = requestedRPM >= configuration.softLimiterRPM
            && state.rpm >= configuration.softLimiterRPM - 100
        let limitedRPM = min(configuration.softLimiterRPM, requestedRPM)
            - (state.isOnLimiter ? 80 : 0)
        state.targetRPM = min(configuration.hardLimiterRPM,
                              max(configuration.idleRPM, limitedRPM))
        if state.isOnLimiter { operatingMode = .limiter }
        state.rpm = min(configuration.hardLimiterRPM, max(configuration.idleRPM,
            approach(state.rpm, state.targetRPM, rate: rate * tuning.rpmResponse / tuning.inertia, dt: deltaTime)))
        state.normalizedRPM = min(1, state.rpm / configuration.redlineRPM)
    }

    private func approach(_ current: Double, _ target: Double, rate: Double, dt: Double) -> Double {
        // Exponential interpolation cannot overshoot, even when a frame takes longer.
        current + (target - current) * (1 - exp(-rate * dt))
    }
}

import Foundation

@MainActor final class SimulationInputProvider: VehicleInputProvider {
    private(set) var currentState = VehicleState()
    private(set) var didDetectLift = false
    private var previousSpeed = 0.0
    private var previousAcceleration = 0.0
    private var previousThrottle = 0.0
    private var foreground = true
    private var usesSensorFixture = false

    func start() { }
    func stop() {
        usesSensorFixture = false
        currentState = VehicleState()
        previousSpeed = 0; previousAcceleration = 0; previousThrottle = 0
        didDetectLift = false
    }
    func setForeground(_ active: Bool) { foreground = active }
    func setInputs(speed: Double? = nil, throttle: Double? = nil, brake: Double? = nil) {
        usesSensorFixture = false
        func bounded(_ value: Double, _ maximum: Double) -> Double {
            value.isFinite ? min(maximum, max(0, value)) : 0
        }
        if let speed { currentState.speedKmh = bounded(speed, 250) }
        if let throttle { currentState.estimatedThrottle = bounded(throttle, 1) }
        if let brake { currentState.brakeInput = bounded(brake, 1) }
        currentState.detectedStopped = nil
        currentState.gpsSpeedKmh = nil; currentState.gpsSpeedAccuracy = nil
        currentState.isGpsValid = false
        currentState.didDetectThrottleLift = false
        currentState.predictedSpeedKmh = currentState.speedKmh
        currentState.rawEstimatedThrottle = currentState.estimatedThrottle
    }
    func setSensorState(_ state: VehicleState, lift: Bool) {
        usesSensorFixture = true; currentState = state; didDetectLift = lift
    }
    @discardableResult func update(deltaTime: Double) -> VehicleState {
        guard foreground, deltaTime.isFinite, deltaTime > 0 else { return currentState }
        if usesSensorFixture { return currentState }
        currentState.predictedSpeedKmh = currentState.speedKmh
        currentState.rawEstimatedThrottle = currentState.estimatedThrottle
        currentState.accelerationMs2 = (currentState.speedKmh - previousSpeed) / 3.6 / deltaTime
        currentState.smoothedAccelerationMs2 = currentState.accelerationMs2
        currentState.jerkMs3 = (currentState.accelerationMs2 - previousAcceleration) / deltaTime
        didDetectLift = previousThrottle > 0.6 && currentState.estimatedThrottle < 0.15
        currentState.didDetectThrottleLift = didDetectLift
        previousSpeed = currentState.speedKmh
        previousAcceleration = currentState.accelerationMs2
        previousThrottle = currentState.estimatedThrottle
        return currentState
    }
}

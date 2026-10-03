import Foundation

@MainActor final class SimulationInputProvider: VehicleInputProvider {
    private(set) var currentState = VehicleState()
    private(set) var didDetectLift = false
    private var previousSpeed = 0.0
    private var previousAcceleration = 0.0
    private var previousThrottle = 0.0
    private var foreground = true

    func start() { }
    func stop() {
        currentState = VehicleState()
        previousSpeed = 0; previousAcceleration = 0; previousThrottle = 0
        didDetectLift = false
    }
    func setForeground(_ active: Bool) { foreground = active }
    func setInputs(speed: Double? = nil, throttle: Double? = nil, brake: Double? = nil) {
        func bounded(_ value: Double, _ maximum: Double) -> Double {
            value.isFinite ? min(maximum, max(0, value)) : 0
        }
        if let speed { currentState.speedKmh = bounded(speed, 250) }
        if let throttle { currentState.estimatedThrottle = bounded(throttle, 1) }
        if let brake { currentState.brakeInput = bounded(brake, 1) }
    }
    @discardableResult func update(deltaTime: Double) -> VehicleState {
        guard foreground, deltaTime.isFinite, deltaTime > 0 else { return currentState }
        currentState.accelerationMs2 = (currentState.speedKmh - previousSpeed) / 3.6 / deltaTime
        currentState.smoothedAccelerationMs2 = currentState.accelerationMs2
        currentState.jerkMs3 = (currentState.accelerationMs2 - previousAcceleration) / deltaTime
        didDetectLift = previousThrottle > 0.6 && currentState.estimatedThrottle < 0.15
        previousSpeed = currentState.speedKmh
        previousAcceleration = currentState.accelerationMs2
        previousThrottle = currentState.estimatedThrottle
        return currentState
    }
}

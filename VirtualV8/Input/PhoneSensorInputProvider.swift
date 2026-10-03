import Foundation

/// Reuses the existing acquisition/estimation coordinator. Permission requests remain explicit.
@MainActor final class PhoneSensorInputProvider: VehicleInputProvider {
    let sensors: SensorInputController
    var currentState: VehicleState { sensors.estimator.state }
    var didDetectLift: Bool { sensors.estimator.didDetectLift }
    init(sensors: SensorInputController? = nil) { self.sensors = sensors ?? SensorInputController() }
    func start() { sensors.enable() }
    func stop() { sensors.disable() }
    func setForeground(_ active: Bool) { sensors.setForeground(active) }
    @discardableResult func update(deltaTime: Double) -> VehicleState { sensors.update(deltaTime: deltaTime) }
}

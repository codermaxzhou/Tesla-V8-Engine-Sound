import Foundation

/// Main-actor ownership keeps acquisition, source switching and published state serialized.
/// Providers translate their source into the same vehicle units; downstream models see no hardware.
@MainActor protocol VehicleInputProvider: AnyObject {
    var currentState: VehicleState { get }
    var didDetectLift: Bool { get }
    func start()
    func stop()
    func setForeground(_ active: Bool)
    @discardableResult func update(deltaTime: Double) -> VehicleState
}

extension VehicleInputProvider {
    var didDetectLift: Bool { false }
}

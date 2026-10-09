import XCTest
@testable import VirtualV8

final class EstimatorTests: XCTestCase {
    private let dt = 1.0 / 60
    private func gps(_ speed: Double, _ time: Double, accuracy: Double = 5) -> LocationSample {
        LocationSample(speedKmh: speed * 3.6, timestamp: time, horizontalAccuracy: accuracy, speedAccuracy: 0.3)
    }
    private func motion(_ acceleration: Double, _ time: Double, axis: SensorVector = SensorVector(x: 1, y: 0, z: 0)) -> MotionSample {
        let vector = SensorVector(x: acceleration * axis.x, y: acceleration * axis.y, z: 0)
        return MotionSample(userAcceleration: vector, gravity: SensorVector(x: 0, y: 0, z: -1),
                            horizontalAcceleration: vector, rotationRate: 0, timestamp: time)
    }
    private func drive(_ estimator: inout VehicleStateEstimator, acceleration: Double, seconds: Int,
                       time: inout Double, speed: inout Double,
                       axis: SensorVector = SensorVector(x: 1, y: 0, z: 0)) {
        for i in 1...(seconds * 60) {
            time += dt
            speed = max(0, speed + acceleration * dt)
            estimator.ingest(motion: motion(acceleration, time, axis: axis), now: time)
            if i % 60 == 0 { estimator.ingest(location: gps(speed, time), now: time) }
            _ = estimator.update(now: time, deltaTime: dt)
        }
    }
    private func movingEstimator() -> VehicleStateEstimator {
        var estimator = VehicleStateEstimator()
        estimator.ingest(location: gps(10, 0), now: 0)
        _ = estimator.update(now: 0, deltaTime: dt)
        return estimator
    }

    func testAccelerationSmoothingAndMountOrientationCalibration() {
        var estimator = movingEstimator(), time = 0.0, speed = 10.0
        let sideways = SensorVector(x: 0, y: -1, z: 0)
        drive(&estimator, acceleration: 3, seconds: 2, time: &time, speed: &speed, axis: sideways)
        XCTAssertNotNil(estimator.forwardAxis)
        XCTAssertEqual(estimator.forwardAxis?.y ?? 0, -1, accuracy: 0.01)
        let previous = estimator.state.smoothedAccelerationMs2
        time += dt
        estimator.ingest(motion: motion(0, time, axis: sideways), now: time)
        let state = estimator.update(now: time, deltaTime: dt)
        XCTAssertEqual(state.accelerationMs2, 0, accuracy: 0.01)
        XCTAssertGreaterThan(state.smoothedAccelerationMs2, 0)
        XCTAssertLessThan(state.smoothedAccelerationMs2, previous)
        XCTAssertTrue(state.jerkMs3.isFinite)
    }

    func testThrottleStrengthAndBounds() {
        var values: [Double] = []
        for acceleration in [0.7, 2.0, 4.0] {
            var estimator = movingEstimator(), time = 0.0, speed = 10.0
            drive(&estimator, acceleration: acceleration, seconds: 5, time: &time, speed: &speed)
            values.append(estimator.state.estimatedThrottle)
            XCTAssertTrue((0...1).contains(estimator.state.estimatedThrottle))
        }
        XCTAssertTrue((0.1...0.3).contains(values[0]))
        XCTAssertTrue((0.3...0.6).contains(values[1]))
        XCTAssertTrue((0.6...1).contains(values[2]))
    }

    func testStoppedDetectionRequiresDurationAndResistsMotionNoise() {
        var estimator = movingEstimator()
        // A long GPS gap allows an ordinary stop to be accepted without an impossible jump.
        estimator.ingest(location: gps(0, 5), now: 5)
        var time = 5.0
        for _ in 0..<30 { time += dt; _ = estimator.update(now: time, deltaTime: dt) }
        XCTAssertFalse(estimator.state.isStopped)
        for i in 0..<2400 {
            time += dt
            if i % 60 == 0 { estimator.ingest(location: gps(0, time), now: time) }
            estimator.ingest(motion: motion(i % 2 == 0 ? 0.1 : -0.1, time), now: time)
            _ = estimator.update(now: time, deltaTime: dt)
        }
        XCTAssertTrue(estimator.state.isStopped)
        XCTAssertFalse(estimator.state.isAccelerating)
        XCTAssertFalse(estimator.state.isDecelerating)
        XCTAssertEqual(estimator.state.estimatedThrottle, 0)
    }

    func testNoisyInvalidAndOutOfOrderSamplesAreRejected() {
        var estimator = movingEstimator()
        estimator.ingest(location: gps(200, 0.5), now: 0.5)
        estimator.ingest(location: gps(10, 1, accuracy: 200), now: 1)
        estimator.ingest(location: gps(-1, 1), now: 1)
        estimator.ingest(location: gps(10, -1), now: 1)
        estimator.ingest(location: gps(10, 10), now: 1)
        estimator.ingest(location: gps(.nan, 1), now: 1)
        var sample = motion(40, 1)
        estimator.ingest(motion: sample, now: 1)
        sample = motion(2, 1); sample.rotationRate = 4
        estimator.ingest(motion: sample, now: 1)
        XCTAssertEqual(estimator.rejectedLocationCount, 6)
        XCTAssertEqual(estimator.rejectedMotionCount, 2)
        XCTAssertEqual(estimator.location?.speedKmh, 36)
        XCTAssertNil(estimator.motion)
    }

    func testSuddenLiftDropsThrottleQuicklyWithoutOscillation() {
        var estimator = movingEstimator(), time = 0.0, speed = 10.0
        drive(&estimator, acceleration: 4, seconds: 5, time: &time, speed: &speed)
        XCTAssertGreaterThan(estimator.state.estimatedThrottle, 0.8)
        var detected = false
        var previous = estimator.state.estimatedThrottle
        for _ in 0..<24 {
            time += dt
            estimator.ingest(motion: motion(0, time), now: time)
            let state = estimator.update(now: time, deltaTime: dt)
            detected = detected || estimator.didDetectLift
            XCTAssertLessThanOrEqual(state.estimatedThrottle, previous + 0.001)
            previous = state.estimatedThrottle
        }
        XCTAssertTrue(detected)
        XCTAssertLessThan(estimator.state.estimatedThrottle, 0.05)
    }

    func testGPSFallbackHoldsThenDecaysAndRecovers() {
        var estimator = movingEstimator()
        for i in 1...240 { _ = estimator.update(now: Double(i) * dt, deltaTime: dt) }
        XCTAssertEqual(estimator.state.speedKmh, 36, accuracy: 0.1)
        XCTAssertEqual(estimator.gpsStatus(now: 4), "Signal lost — holding")
        for i in 241...480 { _ = estimator.update(now: Double(i) * dt, deltaTime: dt) }
        XCTAssertLessThan(estimator.state.speedKmh, 36)
        XCTAssertGreaterThan(estimator.state.speedKmh, 25)
        estimator.ingest(location: gps(10, 8), now: 8)
        let state = estimator.update(now: 8, deltaTime: dt)
        XCTAssertGreaterThan(state.speedKmh, 25)
        XCTAssertEqual(estimator.gpsStatus(now: 8), "Available")
    }

    func testRecoveryAfterLongOutageDoesNotSnapToNewGPSSpeed() {
        var estimator = movingEstimator()
        for i in 1...1800 { _ = estimator.update(now: Double(i) * dt, deltaTime: dt) }
        XCTAssertEqual(estimator.state.speedKmh, 0, accuracy: 0.1)
        estimator.ingest(location: gps(15, 30), now: 30)
        let state = estimator.update(now: 30, deltaTime: dt)
        XCTAssertGreaterThan(state.speedKmh, 0)
        XCTAssertLessThan(state.speedKmh, 5)
        XCTAssertEqual(estimator.gpsStatus(now: 30), "Available")
    }

    func testLateralAccelerationDoesNotBecomeThrottleAfterCalibration() {
        var estimator = movingEstimator(), time = 0.0, speed = 10.0
        drive(&estimator, acceleration: 2, seconds: 3, time: &time, speed: &speed)
        for i in 1...120 {
            time += dt
            estimator.ingest(motion: motion(3, time, axis: SensorVector(x: 0, y: 1, z: 0)), now: time)
            if i % 60 == 0 { estimator.ingest(location: gps(speed, time), now: time) }
            _ = estimator.update(now: time, deltaTime: dt)
        }
        XCTAssertEqual(estimator.state.accelerationMs2, 0, accuracy: 0.01)
        XCTAssertLessThan(estimator.state.estimatedThrottle, 0.03)
    }


    func testMissingGPSCannotCreateSpeedOrThrottleFromPhoneMovement() {
        var estimator = VehicleStateEstimator()
        for i in 1...120 {
            let time = Double(i) * dt
            estimator.ingest(motion: motion(4, time), now: time)
            _ = estimator.update(now: time, deltaTime: dt)
        }
        XCTAssertEqual(estimator.state.speedKmh, 0)
        XCTAssertEqual(estimator.state.estimatedThrottle, 0)
        XCTAssertTrue(estimator.state.isStopped)
        XCTAssertNil(estimator.forwardAxis)
    }

    func testSmallGPSNoiseDoesNotOscillateThrottleAndStaleMotionFallsBack() {
        var estimator = movingEstimator()
        for i in 1...360 {
            let time = Double(i) * dt
            if i % 60 == 0 {
                estimator.ingest(location: gps(i % 120 == 0 ? 10.02 : 9.98, time), now: time)
            }
            _ = estimator.update(now: time, deltaTime: dt)
            XCTAssertLessThan(estimator.state.estimatedThrottle, 0.01)
        }
        var time = 6.0, speed = 10.0
        drive(&estimator, acceleration: 2, seconds: 3, time: &time, speed: &speed)
        XCTAssertNotNil(estimator.forwardAxis)
        estimator.ingest(location: gps(speed, time + 1), now: time + 1)
        let state = estimator.update(now: time + 1, deltaTime: dt)
        XCTAssertEqual(state.accelerationMs2, 0, accuracy: 0.01)
    }

    func testBrakingEstimatesBrakeAndInvalidDeltaDoesNotCorruptState() {
        var estimator = movingEstimator(), time = 0.0, speed = 10.0
        drive(&estimator, acceleration: -2, seconds: 3, time: &time, speed: &speed)
        XCTAssertGreaterThan(estimator.state.brakeInput, 0.2)
        XCTAssertLessThan(estimator.state.estimatedThrottle, 0.01)
        XCTAssertTrue(estimator.state.isDecelerating)
        let rpmInputSpeed = estimator.state.speedKmh
        _ = estimator.update(now: .nan, deltaTime: dt)
        _ = estimator.update(now: time, deltaTime: .nan)
        XCTAssertEqual(estimator.state.speedKmh, rpmInputSpeed)
    }

    @MainActor func testBackgroundPausesAndClearsStaleSensorSamples() async {
        let sensors = SensorInputController()
        sensors.ingest(location: gps(10, 1), now: 1)
        _ = sensors.update(deltaTime: dt, now: 1)
        sensors.setForeground(false)
        _ = sensors.update(deltaTime: dt, now: 100)
        XCTAssertEqual(sensors.gpsStatus, "Paused")
        XCTAssertNil(sensors.estimator.location)
        XCTAssertFalse(sensors.motionAvailable)
        XCTAssertFalse(sensors.locationManager.isSampling)
        sensors.setForeground(true)
        XCTAssertFalse(sensors.sensorsEnabled)
        XCTAssertFalse(sensors.locationManager.isSampling)
    }

    @MainActor func testSensorPipelinePreservesSimulationAndEngineStartStop() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.selectInputMode(.realDrive)
        let now = Date().timeIntervalSince1970
        // Feed a completed straight-line mount calibration before this replay. The
        // estimator no longer gates fresh motion on the next GPS-derived acceleration.
        controller.sensors.beginCalibration()
        for i in 1...210 {
            let t = now - 6 + Double(i) * 0.02
            controller.sensors.ingest(motion: motion(3, t), now: t)
        }
        controller.sensors.ingest(location: gps(15, now - 1), now: now - 1)
        for i in 1...49 {
            let sampleTime = now - 1 + Double(i) * 0.02
            controller.sensors.ingest(motion: motion(3, sampleTime), now: sampleTime)
        }
        controller.sensors.ingest(location: gps(18, now), now: now)
        controller.startEngine()
        controller.advance(seconds: 2)
        XCTAssertGreaterThan(controller.vehicle.speedKmh, 60)
        XCTAssertGreaterThan(controller.vehicle.estimatedThrottle, 0.6)
        XCTAssertGreaterThan(controller.engine.load, 0.3)
        XCTAssertGreaterThan(controller.engine.rpm, 1000)
        XCTAssertGreaterThan(controller.audio.layerGains[.highLoad, default: 0], 0)
        XCTAssertTrue(controller.engine.isRunning)
        let realSpeed = controller.vehicle.speedKmh
        controller.stopEngine()
        XCTAssertFalse(controller.engine.isRunning)
        XCTAssertEqual(controller.vehicle.speedKmh, realSpeed, accuracy: 0.01)
        controller.startDemo()
        XCTAssertEqual(controller.inputMode, .simulation)
        XCTAssertFalse(controller.sensors.sensorsEnabled)
        controller.advance(seconds: DemoSequence.duration)
        XCTAssertFalse(controller.isDemoRunning)
        XCTAssertTrue(controller.engine.isRunning)
        XCTAssertTrue(controller.vehicle.isStopped)
        controller.setThrottle(0.6); controller.setSpeed(50)
        XCTAssertEqual(controller.vehicle.estimatedThrottle, 0.6)
        XCTAssertEqual(controller.vehicle.speedKmh, 50)
    }
}

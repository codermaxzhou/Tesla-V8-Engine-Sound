import XCTest
@testable import VirtualV8

final class LatencyEstimatorTests: XCTestCase {
    private func motion(_ a: Double, _ time: Double, axis: SensorVector = SensorVector(x: 1, y: 0, z: 0)) -> MotionSample {
        let v = SensorVector(x: a * axis.x, y: a * axis.y, z: a * axis.z)
        return MotionSample(userAcceleration: v, gravity: SensorVector(x: 0, y: 0, z: -1),
                            horizontalAcceleration: v, rotationRate: 0, timestamp: time)
    }
    private func gps(_ ms: Double, _ time: Double) -> LocationSample {
        LocationSample(speedKmh: ms * 3.6, timestamp: time, horizontalAccuracy: 3, speedAccuracy: 0.3)
    }
    private func calibrated(speed: Double = 0) -> VehicleStateEstimator {
        var e = VehicleStateEstimator()
        e.restoreForwardAxis(SensorVector(x: 1, y: 0, z: 0))
        e.ingest(location: gps(speed, 0), now: 0)
        return e
    }
    func testAudioAttackDoesNotWaitForEngineLoadOrGPS() {
        var mix = AudioMixModel(seed: 1)
        let vehicle = VehicleState(accelerationMs2: 3, jerkMs3: 8, estimatedThrottle: 0.5)
        var engine = EngineState(rpm: 750); engine.isRunning = true
        _ = mix.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(),
            mode: .acceleration, drivingMode: .sport, tuning: AudioTuning(), deltaTime: 0.02)
        XCTAssertEqual(engine.load, 0)
        XCTAssertGreaterThan(mix.gains[.highLoad, default: 0], 0.04)
        XCTAssertGreaterThan(mix.gains[.intake, default: 0], 0.02)
    }
    func testDetectedLiftEntersOverrunBeforeFilteredThrottleSettlesAndCanBackfire() {
        var engine = VirtualEngine()
        let transmission = VirtualTransmission()
        engine.start()
        for _ in 0..<180 {
            engine.update(deltaTime: 1.0 / 60, vehicle: VehicleState(estimatedThrottle: 0.8),
                          transmission: transmission, drivingMode: .sport)
        }
        let priorRPM = engine.state.rpm
        let lift = VehicleState(speedKmh: 20, accelerationMs2: 0, estimatedThrottle: 0.7,
                                rawEstimatedThrottle: 0, didDetectThrottleLift: true)
        engine.update(deltaTime: 1.0 / 60, vehicle: lift, transmission: transmission, drivingMode: .sport)
        XCTAssertEqual(engine.operatingMode, .overrun)
        XCTAssertLessThan(engine.state.targetRPM, priorRPM)
        XCTAssertLessThan(engine.state.rpm, priorRPM)
        var eligiblePops = 0
        for seed in 1...100 {
            var mix = AudioMixModel(seed: UInt64(seed))
            var state = EngineState(rpm: 4500); state.isRunning = true; state.load = 0.6
            _ = mix.update(engine: state, vehicle: VehicleState(estimatedThrottle: 0.8), transmission: TransmissionState(),
                mode: .fullLoad, drivingMode: .track, tuning: AudioTuning(), deltaTime: 0.02)
            let events = mix.update(engine: state, vehicle: lift, transmission: TransmissionState(),
                mode: .overrun, drivingMode: .track, tuning: AudioTuning(), deltaTime: 0.02)
            eligiblePops += events.filter { $0.layer == .backfire }.count
        }
        XCTAssertGreaterThan(eligiblePops, 0)
        XCTAssertLessThan(eligiblePops, 100) // probability/cooldown behavior is preserved
    }
    func testAccelerationAlphaAndActualTimestampJerk() {
        var e = calibrated(speed: 10)
        e.ingest(motion: motion(0, 0.01), now: 0.01)
        e.ingest(motion: motion(2, 0.03), now: 0.03)
        let s = e.update(now: 0.03, deltaTime: 0.02)
        XCTAssertEqual(s.smoothedAccelerationMs2, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.jerkMs3, 7.5, accuracy: 1e-9)
        e.ingest(motion: motion(2, 0.07), now: 0.07)
        let next = e.update(now: 0.07, deltaTime: 0.04)
        XCTAssertEqual(next.smoothedAccelerationMs2, 0.6 + 1.4 * 0.51, accuracy: 1e-9)
    }
    func testThrottleAttackBeforeAnyNewGPSAndLaunchWhileStopped() {
        var e = calibrated()
        for i in 1...4 {
            let t = Double(i) * 0.02
            e.ingest(motion: motion(3.2, t), now: t)
            _ = e.update(now: t, deltaTime: 0.02)
        }
        XCTAssertEqual(e.location?.timestamp, 0)
        XCTAssertGreaterThan(e.state.estimatedThrottle, 0.35)
        XCTAssertGreaterThan(e.predictedSpeedMs, 0)
        XCTAssertFalse(e.state.isStopped)
        XCTAssertTrue(e.state.isAccelerating)
    }
    func testAsymmetricReleaseAndLiftWithin80Milliseconds() {
        var e = calibrated(speed: 10)
        for i in 1...100 {
            let t = Double(i) * 0.02
            e.ingest(motion: motion(4, t), now: t); _ = e.update(now: t, deltaTime: 0.02)
        }
        let initial = e.state.estimatedThrottle
        var lifted = false
        for i in 101...104 {
            let t = Double(i) * 0.02
            e.ingest(motion: motion(0, t), now: t); _ = e.update(now: t, deltaTime: 0.02)
            lifted = lifted || e.didDetectLift
        }
        XCTAssertTrue(lifted)
        XCTAssertLessThan(e.state.estimatedThrottle, initial * 0.5)
        for i in 105...120 {
            let t = Double(i) * 0.02
            e.ingest(motion: motion(0, t), now: t); _ = e.update(now: t, deltaTime: 0.02)
        }
        XCTAssertLessThan(e.state.estimatedThrottle, 0.03)
    }
    func testPredictedSpeedIntegratesDuringFiveSecondGPSDropout() {
        var e = calibrated(speed: 10)
        for i in 1...300 {
            let t = Double(i) * 0.02
            e.ingest(motion: motion(2, t), now: t); _ = e.update(now: t, deltaTime: 0.02)
        }
        XCTAssertGreaterThan(e.predictedSpeedMs, 19)
        XCTAssertLessThan(e.predictedSpeedMs, 23)
        XCTAssertFalse(e.state.isGpsValid)
        XCTAssertGreaterThan(e.state.estimatedThrottle, 0.4)
        XCTAssertGreaterThan(e.speedUncertaintyMs, 0)
    }
    func testGPSCorrectionIsGradualAndConvergesAtRest() {
        var e = calibrated(speed: 10)
        e.ingest(location: gps(12, 1), now: 1)
        let first = e.update(now: 1, deltaTime: 0.02)
        XCTAssertGreaterThan(first.speedKmh, 36)
        XCTAssertLessThan(first.speedKmh, 36.1)
        for i in 1...3000 {
            let t = 1 + Double(i) * 0.02
            if i % 50 == 0 { e.ingest(location: gps(12, t), now: t) }
            e.ingest(motion: motion(0, t), now: t)
            _ = e.update(now: t, deltaTime: 0.02)
        }
        XCTAssertEqual(e.predictedSpeedMs, 12, accuracy: 0.02)
    }
    func testReturningGPSDoesNotSnapAfterLongOutage() {
        var e = calibrated(speed: 10)
        for i in 1...2000 { _ = e.update(now: Double(i) * 0.02, deltaTime: 0.02) }
        let before = e.predictedSpeedMs
        e.ingest(location: gps(15, 40), now: 40)
        _ = e.update(now: 40, deltaTime: 0.02)
        XCTAssertGreaterThan(e.predictedSpeedMs, before)
        XCTAssertLessThan(e.predictedSpeedMs - before, 0.1)
    }
    func testNegativePredictionIsClampedAndNoiseDoesNotCreateThrottle() {
        var e = calibrated()
        for i in 1...300 {
            let t = Double(i) * 0.02
            let a = i < 100 ? -3 : (i % 2 == 0 ? 0.15 : -0.15)
            e.ingest(motion: motion(a, t), now: t); _ = e.update(now: t, deltaTime: 0.02)
            XCTAssertGreaterThanOrEqual(e.predictedSpeedMs, 0)
            XCTAssertLessThan(e.state.estimatedThrottle, 0.02)
        }
    }
    func testCalibrationDominantAxisAndTiltedMount() {
        var e = VehicleStateEstimator()
        e.beginCalibration()
        let axis = SensorVector(x: 0.6, y: 0.8, z: 0)
        for i in 1...210 {
            let t = Double(i) * 0.02
            e.ingest(motion: motion(2, t, axis: axis), now: t)
            _ = e.update(now: t, deltaTime: 0.02)
        }
        XCTAssertFalse(e.calibration.isCollecting)
        XCTAssertEqual(e.forwardAxis?.x ?? 0, 0.6, accuracy: 0.01)
        XCTAssertEqual(e.forwardAxis?.y ?? 0, 0.8, accuracy: 0.01)
        e.ingest(motion: motion(3, 4.3, axis: axis), now: 4.3)
        _ = e.update(now: 4.3, deltaTime: 0.02)
        XCTAssertEqual(e.rawAcceleration, 3, accuracy: 1e-9)
        // Horizontal projection in a tilted device frame removes vertical acceleration.
        var tilted = e
        tilted.resetCalibration()
        tilted.restoreForwardAxis(SensorVector(x: 1, y: 0, z: 0))
        let sample = MotionSample(userAcceleration: SensorVector(x: 2, y: 1, z: 0),
            gravity: SensorVector(x: 0, y: -1, z: 0), horizontalAcceleration: SensorVector(x: 2, y: 0, z: 0),
            rotationRate: 0, timestamp: 4.4)
        tilted.ingest(motion: sample, now: 4.4)
        XCTAssertEqual(tilted.rawAcceleration, 2, accuracy: 1e-9)
    }
    func testLatencyScenariosUse50HzMotionAnd1HzGPSWithoutSnapping() {
        for scenario in [SimulationScenario.suddenAcceleration, .throttleLift, .gpsLag, .gpsDropout] {
            var runner = LatencyScenarioRunner(tuning: EstimatorTuning())
            var previous = 0.0, peak = 0.0, lifted = false
            for i in 1...2700 {
                let s = runner.update(scenario: scenario, dt: 1.0 / 60, tuning: EstimatorTuning())
                XCTAssertLessThan(abs(s.speedKmh - previous), 0.3)
                previous = s.speedKmh; peak = max(peak, s.speedKmh)
                lifted = lifted || runner.estimator.didDetectLift
                if i == 125 { XCTAssertGreaterThan(s.estimatedThrottle, 0.25) }
                if scenario == .gpsDropout, i == 420 { XCTAssertGreaterThan(s.speedKmh, 35) }
            }
            XCTAssertEqual(runner.motionSamples, 2250)
            XCTAssertGreaterThan(runner.gpsSamples, 30)
            XCTAssertLessThanOrEqual(runner.gpsSamples, 45)
            XCTAssertGreaterThan(peak, 35)
            XCTAssertTrue(lifted)
            XCTAssertTrue(runner.estimator.state.isStopped)
        }
    }
    @MainActor func testPhysicalDeviceMotionDeliveryAndStationaryEstimator() async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        let sensors = SensorInputController()
        guard sensors.motionManager.isAvailable else { throw XCTSkip("Device motion unavailable") }
        sensors.motionManager.start()
        defer { sensors.motionManager.stop() }
        var measuredIntervals: [Double] = []
        var priorTimestamp: Double?
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            _ = sensors.update(deltaTime: 0.02)
            if let t = sensors.estimator.motion?.timestamp, t != priorTimestamp {
                if let priorTimestamp { measuredIntervals.append(t - priorTimestamp) }
                priorTimestamp = t
            }
        }
        XCTAssertTrue(sensors.motionAvailable, sensors.motionManager.status)
        XCTAssertGreaterThan(measuredIntervals.count, 50)
        XCTAssertTrue(measuredIntervals.allSatisfy { $0 > 0 && $0 < 0.15 })
        XCTAssertGreaterThan(sensors.estimator.motionFrequencyHz, 30)
        XCTAssertLessThan(sensors.estimator.motionFrequencyHz, 100)
        XCTAssertNotNil(sensors.estimator.motion?.attitude)
        XCTAssertTrue(sensors.estimator.state.speedKmh.isFinite)
        XCTAssertTrue((0...1).contains(sensors.estimator.state.estimatedThrottle))
        #else
        throw XCTSkip("Requires a connected physical iPhone")
        #endif
    }
    @MainActor func testLatencyHistoryIsBoundedAndManualControlsCancelSensorFixtures() async {
        let c = SimulationController(automaticallyTicks: false)
        c.startScenario(.gpsLag)
        c.advance(seconds: 12)
        XCTAssertEqual(c.logger.latencyHistory.count, 200)
        XCTAssertEqual(Set(c.logger.latencyHistory.map(\.id)).count, 200)
        XCTAssertNotNil(c.logger.latencyHistory.last?.gpsSpeed)
        c.setThrottle(0.6); c.setSpeed(50)
        c.advance(seconds: 0.1)
        XCTAssertFalse(c.isDemoRunning)
        XCTAssertEqual(c.vehicle.estimatedThrottle, 0.6)
        XCTAssertEqual(c.vehicle.speedKmh, 50)
        XCTAssertNil(c.vehicle.gpsSpeedKmh)
        XCTAssertFalse(c.vehicle.isGpsValid)
    }
    @MainActor func testNewSettingsAndOrientationPersistAndOldSchemaMigrates() async throws {
        let name = "LatencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let a = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        a.updateCalibration {
            $0.estimator.gpsCorrectionGain = 0.17; $0.estimator.throttleAttackAlpha = 0.6
            $0.estimator.accelerationSmoothingAlpha = 0.43; $0.estimator.jerkSmoothingAlpha = 0.31
            $0.estimator.throttleReleaseAlpha = 0.27; $0.estimator.accelerationDeadZone = 0.18
            $0.estimator.jerkThreshold = 2.8; $0.estimator.throttleSensitivity = 1.34
        }
        a.sensors.beginCalibration()
        for i in 1...210 { a.sensors.ingest(motion: motion(2, Double(i) * 0.02), now: Double(i) * 0.02) }
        let b = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        XCTAssertEqual(b.sensors.tuning, a.calibration.values.estimator)
        XCTAssertEqual(b.sensors.tuning.gpsCorrectionGain, 0.17)
        XCTAssertEqual(b.sensors.tuning.throttleAttackAlpha, 0.6)
        XCTAssertEqual(b.sensors.estimator.forwardAxis?.x, 1)
        b.sensors.setForeground(false); b.sensors.setForeground(true)
        XCTAssertEqual(b.sensors.estimator.forwardAxis?.x, 1)
        let old = Data("{\"throttleSensitivity\":1.2,\"accelerationSmoothing\":0.8,\"throttleSmoothing\":0.9,\"stoppedDuration\":2}".utf8)
        let migrated = try JSONDecoder().decode(EstimatorTuning.self, from: old)
        XCTAssertEqual(migrated.throttleSensitivity, 1.2)
        XCTAssertEqual(migrated.stoppedDuration, 2)
        XCTAssertEqual(migrated.accelerationSmoothingAlpha, 0.3)
    }

    @MainActor func testPhoneProviderToEngineAndLoadAudioRespondWithin80MsBeforeGPS() async {
        let provider = ClockedPhoneInput()
        let c = SimulationController(automaticallyTicks: false, inputProvider: provider)
        provider.sensors.ingest(location: gps(0, 0), now: 0)
        provider.sensors.beginCalibration()
        for i in 1...210 {
            let t = -5 + Double(i) * 0.02
            provider.sensors.ingest(motion: motion(2, t), now: t)
        }
        c.startEngine()
        for i in 1...120 {
            provider.now = Double(i) / 60
            provider.sensors.ingest(motion: motion(0, provider.now), now: provider.now)
            c.advance(seconds: 1.0 / 60)
        }
        let idle = c.engine.rpm
        for i in 121...124 {
            provider.now = Double(i) / 60
            provider.sensors.ingest(motion: motion(3.2, provider.now), now: provider.now)
            c.advance(seconds: 1.0 / 60)
        }
        XCTAssertEqual(provider.sensors.estimator.location?.timestamp, 0)
        XCTAssertGreaterThan(c.vehicle.estimatedThrottle, 0.3)
        XCTAssertGreaterThan(c.engine.rpm, idle + 20)
        XCTAssertGreaterThan(c.engine.load, 0)
        XCTAssertGreaterThan(c.audio.layerGains[.highLoad, default: 0], 0)
        XCTAssertGreaterThan(c.audio.layerGains[.intake, default: 0], 0)
    }
}

@MainActor private final class ClockedPhoneInput: VehicleInputProvider {
    let sensors = SensorInputController()
    var now = 0.0
    var currentState: VehicleState { sensors.estimator.state }
    var didDetectLift: Bool { sensors.estimator.didDetectLift }
    func start() {}
    func stop() { sensors.disable() }
    func setForeground(_ active: Bool) { sensors.setForeground(active) }
    func update(deltaTime: Double) -> VehicleState { sensors.update(deltaTime: deltaTime, now: now) }
}

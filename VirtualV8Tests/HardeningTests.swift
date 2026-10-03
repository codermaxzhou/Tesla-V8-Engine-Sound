import XCTest
@testable import VirtualV8

final class HardeningTests: XCTestCase {
    @MainActor private final class RecordedInput: VehicleInputProvider {
        var currentState = VehicleState()
        var updates = 0
        var stops = 0
        var foreground = true
        func start() { }
        func stop() { stops += 1 }
        func setForeground(_ active: Bool) { foreground = active }
        func update(deltaTime: Double) -> VehicleState { updates += 1; return currentState }
    }

    @MainActor func testInjectedProviderFeedsPowertrainAudioAndLoggerWithoutSensors() {
        let input = RecordedInput()
        input.currentState.speedKmh = 65
        input.currentState.estimatedThrottle = 0.8
        let controller = SimulationController(automaticallyTicks: false, inputProvider: input)
        controller.startEngine(); controller.startLogging()
        controller.advance(seconds: 4)
        XCTAssertEqual(input.updates, 240)
        XCTAssertEqual(controller.vehicle.speedKmh, 65)
        XCTAssertGreaterThan(controller.engine.rpm, 1500)
        XCTAssertGreaterThan(controller.engine.load, 0.3)
        XCTAssertGreaterThan(controller.audio.layerGains[.highLoad, default: 0], 0)
        XCTAssertEqual(controller.logger.records.count, 20)
        XCTAssertFalse(controller.sensors.sensorsEnabled)
        controller.selectInputMode(.realDrive)
        XCTAssertEqual(input.stops, 1)
        XCTAssertEqual(controller.vehicle.speedKmh, 0)
        XCTAssertFalse(controller.sensors.sensorsEnabled, "Selection must not request permission")
    }

    @MainActor func testSimulationProviderBoundsDerivativesAndLift() {
        let input = SimulationInputProvider()
        input.start()
        input.setInputs(speed: 36, throttle: 0.9, brake: -1)
        let first = input.update(deltaTime: 1)
        XCTAssertEqual(first.accelerationMs2, 10)
        XCTAssertEqual(first.jerkMs3, 10)
        XCTAssertEqual(first.brakeInput, 0)
        input.setInputs(throttle: 0)
        _ = input.update(deltaTime: 1)
        XCTAssertTrue(input.didDetectLift)
        _ = input.update(deltaTime: 1)
        XCTAssertFalse(input.didDetectLift)
        input.setInputs(speed: .nan, throttle: 20, brake: .infinity)
        XCTAssertEqual(input.currentState.speedKmh, 0)
        XCTAssertEqual(input.currentState.estimatedThrottle, 1)
        XCTAssertEqual(input.currentState.brakeInput, 0)
        input.stop()
        XCTAssertEqual(input.currentState.estimatedThrottle, 0)
    }

    @MainActor func testPhoneProviderWithoutFixAndForegroundClearsStaleInput() {
        let input = PhoneSensorInputProvider()
        XCTAssertEqual(input.update(deltaTime: 1.0 / 60).speedKmh, 0)
        let now = Date().timeIntervalSince1970
        input.sensors.ingest(location: LocationSample(speedKmh: 40, timestamp: now,
            horizontalAccuracy: 5, speedAccuracy: 0.5), now: now)
        XCTAssertGreaterThan(input.update(deltaTime: 0.1).speedKmh, 0)
        input.setForeground(false)
        XCTAssertEqual(input.currentState.speedKmh, 0)
        XCTAssertNil(input.sensors.estimator.location)
        input.setForeground(true)
        XCTAssertFalse(input.sensors.locationManager.isSampling)
        input.stop()
        XCTAssertFalse(input.sensors.sensorsEnabled)
    }

    @MainActor func testBackgroundFreezesScenarioLoggingAndAudioThenResumesWithoutCatchup() throws {
        let controller = SimulationController(automaticallyTicks: false, audioOutput: .offline)
        defer { controller.audio.shutdown() }
        controller.startDemo(); controller.startLogging(); controller.advance(seconds: 3)
        XCTAssertTrue(controller.audio.isActive)
        let elapsed = controller.demoElapsed
        let rpm = controller.engine.rpm
        let rows = controller.logger.records.count
        controller.setForeground(false)
        XCTAssertFalse(controller.audio.isActive)
        controller.advance(seconds: 100)
        XCTAssertEqual(controller.demoElapsed, elapsed)
        XCTAssertEqual(controller.engine.rpm, rpm)
        XCTAssertEqual(controller.logger.records.count, rows)
        XCTAssertFalse(controller.logger.isLogging)
        controller.setForeground(true)
        controller.advance(seconds: 1.0 / 60)
        XCTAssertTrue(controller.audio.isActive)
        XCTAssertEqual(controller.demoElapsed, elapsed + 1.0 / 60, accuracy: 0.00001)
        _ = try controller.audio.render(frameCount: 512)
    }

    @MainActor func testAudioInterruptionRouteReconnectAndMediaReset() throws {
        let audio = EngineAudioEngine(outputMode: .offline)
        defer { audio.shutdown() }
        var engine = EngineState(); engine.isRunning = true; engine.rpm = 3500
        func tick() {
            audio.update(engine: engine, vehicle: VehicleState(), transmission: TransmissionState(),
                         mode: .cruise, drivingMode: .sport, deltaTime: 1.0 / 60)
        }
        tick(); XCTAssertTrue(audio.isActive)
        audio.handleInterruption(began: true); tick(); XCTAssertFalse(audio.isActive)
        audio.handleInterruption(began: false, shouldResume: false); tick(); XCTAssertFalse(audio.isActive)
        audio.retryPlayback(); tick(); XCTAssertTrue(audio.isActive)
        audio.handleInterruption(began: true)
        audio.handleRouteChange(disconnected: false, reconnected: true)
        tick(); XCTAssertFalse(audio.isActive, "Reconnect must not override an active phone call")
        audio.handleInterruption(began: false, shouldResume: true); tick(); XCTAssertTrue(audio.isActive)
        audio.handleRouteChange(disconnected: true); tick(); XCTAssertFalse(audio.isActive)
        XCTAssertTrue(audio.status.contains("disconnected"))
        audio.handleRouteChange(disconnected: false); tick(); XCTAssertFalse(audio.isActive)
        audio.handleRouteChange(disconnected: false, reconnected: true); tick(); XCTAssertTrue(audio.isActive)
        audio.resetMediaServices(); XCTAssertFalse(audio.isActive)
        tick(); XCTAssertTrue(audio.isActive)
        _ = try audio.render(frameCount: 512)
        XCTAssertNil(audio.errorMessage)
    }

    func testLatencyLookAheadIsBoundedAndResets() {
        var prediction = AudioLatencyCompensator()
        var engine = EngineState(); engine.isRunning = true; engine.rpm = 3000
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 1000, deltaTime: 0.1), 3000)
        engine.rpm = 3100
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 200, deltaTime: 0.1), 3300, accuracy: 0.01)
        engine.rpm = 6500
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 5000, deltaTime: 0.01), 6700)
        engine.rpm = 750
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 1000, deltaTime: 0.01), 750)
        engine.rpm = 2000
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 0, deltaTime: 0.01), 2000)
        prediction.reset(); engine.rpm = 4000
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 1000, deltaTime: 0.01), 4000)
        engine.isRunning = false
        XCTAssertEqual(prediction.rpm(for: engine, milliseconds: 1000, deltaTime: 0.01), 0)
    }

    @MainActor func testLatencyPersistenceBoundsAndPhase5Migration() throws {
        let domain = "VirtualV8.Hardening.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = CalibrationSettings(defaults: defaults)
        settings.update { $0.audio.audioLatencyCompensationMs = 1200; $0.engine.rpmResponse = 1.4 }
        XCTAssertEqual(settings.values.audio.audioLatencyCompensationMs, 1000)
        settings.apply(.sport)
        XCTAssertEqual(settings.values.audio.audioLatencyCompensationMs, 1000)
        let restored = CalibrationSettings(defaults: defaults)
        XCTAssertEqual(restored.values.audio.audioLatencyCompensationMs, 1000)
        restored.restoreCustom()
        XCTAssertEqual(restored.values.engine.rpmResponse, 1.4)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: defaults.data(forKey: CalibrationSettings.storageKey)!) as? [String: Any])
        for key in ["values", "custom"] {
            var values = saved[key] as! [String: Any]
            var audio = values["audio"] as! [String: Any]
            audio.removeValue(forKey: "audioLatencyCompensationMs")
            values["audio"] = audio; saved[key] = values
        }
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: CalibrationSettings.storageKey)
        let migrated = CalibrationSettings(defaults: defaults)
        XCTAssertNil(migrated.persistenceError)
        XCTAssertEqual(migrated.values.engine.rpmResponse, 1.4)
        XCTAssertEqual(migrated.values.audio.audioLatencyCompensationMs, 0)
    }

    @MainActor func testLatencyDoesNotChangeDrivetrainOrShiftEventTiming() {
        let direct = SimulationController(automaticallyTicks: false)
        let compensated = SimulationController(automaticallyTicks: false)
        compensated.updateCalibration { $0.audio.audioLatencyCompensationMs = 1000 }
        direct.startScenario(.fullThrottle)
        compensated.startScenario(.fullThrottle)
        var sawLookAhead = false
        for _ in 0..<Int(SimulationScenario.fullThrottle.duration * 60) {
            direct.advance(seconds: 1.0 / 60); compensated.advance(seconds: 1.0 / 60)
            XCTAssertEqual(direct.engine.rpm, compensated.engine.rpm, accuracy: 0.000001)
            XCTAssertEqual(direct.transmission.currentGear, compensated.transmission.currentGear)
            XCTAssertEqual(direct.audio.lastEvents.filter { $0.layer == .shiftTransient || $0.layer == .revMatch }.count,
                           compensated.audio.lastEvents.filter { $0.layer == .shiftTransient || $0.layer == .revMatch }.count)
            if abs(compensated.audio.compensatedRPM - compensated.engine.rpm) > 50 { sawLookAhead = true }
        }
        XCTAssertTrue(sawLookAhead)
        XCTAssertEqual(compensated.engine.rpm, 750, accuracy: 2)
        XCTAssertEqual(compensated.transmission.currentGear, 1)
        XCTAssertFalse(compensated.isDemoRunning)
    }
}

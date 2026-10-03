import XCTest
@testable import VirtualV8

final class CalibrationLoggingTests: XCTestCase {
    @MainActor func testSavedSettingsRestoreAcrossControllerLaunchesAndPresetsKeepCustom() async {
        let name = "VirtualV8Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        first.updateCalibration {
            $0.engine.rpmResponse = 1.7; $0.engine.inertia = 1.3
            $0.estimator.throttleSensitivity = 1.2; $0.transmission.shiftDuration = 1.25
            $0.audio.engineVolume = 0.64
        }
        first.audio.tuning.intakeVolume = 0.28 // Existing tuning controls also persist.
        first.sensors.tuning.throttleSmoothing = 0.72
        let custom = first.calibration.values
        first.applyPreset(.track)
        XCTAssertEqual(first.calibration.customValues, custom)
        let second = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        XCTAssertEqual(second.calibration.preset, .track)
        XCTAssertEqual(second.calibration.values, CalibrationPreset.track.values)
        second.restoreCustomCalibration()
        XCTAssertEqual(second.calibration.values, custom)
        XCTAssertEqual(second.audio.tuning.engineVolume, 0.64)
        XCTAssertEqual(second.sensors.tuning.throttleSmoothing, 0.72)
        let third = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        XCTAssertNil(third.calibration.preset)
        XCTAssertEqual(third.calibration.values, custom)
    }

    @MainActor func testCalibrationBoundsCorruptStorageAndPresetOrdering() async {
        let untouched = CalibrationSettings()
        untouched.apply(.sport)
        untouched.update {
            $0.engine.rpmResponse = 1.2000000029802322
            $0.audio.engineVolume = 0.8999999761581421
        }
        XCTAssertEqual(untouched.preset, .sport)
        XCTAssertEqual(untouched.values, CalibrationPreset.sport.values)
        let settings = CalibrationSettings()
        settings.update {
            $0.engine.inertia = 0; $0.engine.rpmResponse = .nan
            $0.audio.engineVolume = 10; $0.audio.backfireAmount = -1
            $0.estimator.throttleSensitivity = 20; $0.estimator.accelerationSmoothing = -2
            $0.transmission.shiftDuration = .infinity
        }
        XCTAssertEqual(settings.values.engine.inertia, 0.5)
        XCTAssertEqual(settings.values.engine.rpmResponse, 1)
        XCTAssertEqual(settings.values.audio.engineVolume, 1)
        XCTAssertEqual(settings.values.audio.backfireAmount, 0)
        XCTAssertEqual(settings.values.estimator.throttleSensitivity, 1.5)
        XCTAssertEqual(settings.values.estimator.accelerationSmoothing, 0.05)
        XCTAssertEqual(settings.values.transmission.shiftDuration, 1)
        XCTAssertLessThan(CalibrationPreset.comfort.values.audio.masterVolume, CalibrationPreset.track.values.audio.masterVolume)
        XCTAssertLessThan(CalibrationPreset.comfort.values.engine.rpmResponse, CalibrationPreset.sport.values.engine.rpmResponse)
        let name = "VirtualV8Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("bad JSON".utf8), forKey: CalibrationSettings.storageKey)
        let recovered = CalibrationSettings(defaults: defaults)
        XCTAssertEqual(recovered.values, CalibrationValues())
        XCTAssertNotNil(recovered.persistenceError)
    }

    @MainActor func testCalibrationLocksWhileRealDriveIsMoving() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.selectInputMode(.realDrive)
        let now = Date().timeIntervalSince1970
        controller.sensors.ingest(location: LocationSample(speedKmh: 60, timestamp: now, horizontalAccuracy: 5, speedAccuracy: 0.3), now: now)
        controller.advance(seconds: 0.1)
        XCTAssertFalse(controller.canCalibrate)
        let previous = controller.calibration.values
        controller.applyPreset(.track)
        controller.updateCalibration { $0.engine.rpmResponse = 2 }
        controller.audio.tuning.engineVolume = 0.1
        controller.sensors.tuning.throttleSmoothing = 1.5
        XCTAssertEqual(controller.calibration.values, previous)
        XCTAssertEqual(controller.audio.tuning.engineVolume, previous.audio.engineVolume)
        XCTAssertEqual(controller.sensors.tuning.throttleSmoothing, previous.estimator.throttleSmoothing)
        controller.selectInputMode(.simulation)
        controller.updateCalibration { $0.engine.rpmResponse = 1.8 }
        XCTAssertEqual(controller.calibration.values.engine.rpmResponse, 1.8)
    }

    func testRPMResponseAndInertiaChangeRateWithoutViolatingLimits() {
        var fast = VirtualEngine(), slow = VirtualEngine()
        fast.tuning = EngineTuning(rpmResponse: 2, inertia: 0.5)
        slow.tuning = EngineTuning(rpmResponse: 0.5, inertia: 2)
        let vehicle = VehicleState(estimatedThrottle: 1)
        fast.start(); slow.start()
        for _ in 0..<90 {
            fast.update(deltaTime: 1.0 / 60, vehicle: vehicle, transmission: VirtualTransmission(), drivingMode: .sport)
            slow.update(deltaTime: 1.0 / 60, vehicle: vehicle, transmission: VirtualTransmission(), drivingMode: .sport)
        }
        XCTAssertGreaterThan(fast.state.rpm, slow.state.rpm + 1000)
        XCTAssertLessThanOrEqual(fast.state.rpm, 6700)
        XCTAssertGreaterThanOrEqual(slow.state.rpm, 750)
    }

    func testThrottleSensitivityChangesSensorEstimateWithinBounds() {
        var low = VehicleStateEstimator(), high = VehicleStateEstimator()
        low.tuning.throttleSensitivity = 0.5
        high.tuning.throttleSensitivity = 1.5
        let initial = LocationSample(speedKmh: 36, timestamp: 0, horizontalAccuracy: 5, speedAccuracy: 0.3)
        low.ingest(location: initial, now: 0); high.ingest(location: initial, now: 0)
        for i in 1...300 {
            let time = Double(i) / 60
            if i % 60 == 0 {
                let sample = LocationSample(speedKmh: (10 + 2 * time) * 3.6, timestamp: time, horizontalAccuracy: 5, speedAccuracy: 0.3)
                low.ingest(location: sample, now: time); high.ingest(location: sample, now: time)
            }
            _ = low.update(now: time, deltaTime: 1.0 / 60)
            _ = high.update(now: time, deltaTime: 1.0 / 60)
        }
        XCTAssertGreaterThan(high.state.estimatedThrottle, low.state.estimatedThrottle * 2.5)
        XCTAssertTrue((0...1).contains(high.state.estimatedThrottle))
    }

    func testShiftTuningUsesLatchedDurationAndSurvivesReset() {
        var transmission = VirtualTransmission()
        transmission.tuning = TransmissionTuning(upshiftAggressiveness: 1.1, downshiftAggressiveness: 1.2, shiftDuration: 0.6)
        XCTAssertGreaterThan(transmission.upshiftRPM(throttle: 0.1, mode: .comfort), VirtualTransmission().upshiftRPM(throttle: 0.1, mode: .comfort))
        var engine = EngineState(); engine.isRunning = true; engine.rpm = 5000
        let vehicle = VehicleState(speedKmh: 60, estimatedThrottle: 0.1)
        transmission.update(deltaTime: 1.1, vehicle: vehicle, engine: engine, mode: .comfort, configuration: .americanV8)
        XCTAssertTrue(transmission.state.isShifting)
        let duration = transmission.shiftDuration
        transmission.tuning.shiftDuration = 1.5
        transmission.update(deltaTime: 0.02, vehicle: vehicle, engine: engine, mode: .comfort, configuration: .americanV8)
        XCTAssertEqual(transmission.shiftDuration, duration)
        transmission.reset()
        XCTAssertEqual(transmission.tuning.shiftDuration, 1.5)
    }

    @MainActor func testLoggerFrequencyBoundAndTransientRetention() async {
        let logger = DriveLogger(maximumRecords: 5)
        logger.start()
        var transmission = TransmissionState()
        for i in 0..<90 {
            transmission.isShifting = i == 2
            transmission.shiftType = i == 2 ? .upshift : .none
            logger.sample(deltaTime: 1.0 / 60, timestamp: Date(timeIntervalSince1970: Double(i) / 60),
                          vehicle: VehicleState(speedKmh: 30, estimatedThrottle: 0.8), engine: EngineState(),
                          transmission: transmission, mode: .acceleration, backfire: i == 3)
        }
        XCTAssertEqual(logger.records.count, 5)
        XCTAssertEqual(logger.history.count, 7)
        XCTAssertFalse(logger.isLogging)
        XCTAssertTrue(logger.records[0].backfireEvent)
        XCTAssertEqual(logger.records[0].shiftType, .upshift)
        XCTAssertFalse(logger.records[1].backfireEvent)
        XCTAssertTrue(logger.status.contains("limit"))
        for _ in 0..<500 { logger.sample(deltaTime: 0.2, timestamp: Date(), vehicle: VehicleState(), engine: EngineState(), transmission: TransmissionState(), mode: .idle, backfire: false) }
        XCTAssertEqual(logger.history.count, 300)
        XCTAssertEqual(logger.records.count, 5)
    }

    @MainActor func testCSVExportHasAllFieldsAndMatchesDisk() async throws {
        let logger = DriveLogger()
        logger.start()
        logger.sample(deltaTime: 0.2, timestamp: Date(timeIntervalSince1970: 1234),
                      vehicle: VehicleState(speedKmh: 83.5, accelerationMs2: 2.2, smoothedAccelerationMs2: 1.8, jerkMs3: -0.5, estimatedThrottle: 0.7),
                      engine: EngineState(rpm: 4200), transmission: TransmissionState(), mode: .fullLoad, backfire: true)
        logger.stop()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try logger.exportCSV(directory: folder)
        let csv = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(csv, logger.csv())
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "timestamp,speedKmh,rawAcceleration,filteredAcceleration,jerk,estimatedThrottle,rpm,gear,targetGear,engineMode,shiftType,backfireEvent")
        let fields = lines[1].split(separator: ",")
        XCTAssertEqual(fields.count, 12)
        XCTAssertEqual(fields[1], "83.50000")
        XCTAssertEqual(fields[5], "0.70000")
        XCTAssertEqual(fields[6], "4200.00000")
        XCTAssertEqual(fields[11], "true")
        XCTAssertTrue(fields[0].hasSuffix("Z"))
        XCTAssertEqual(logger.exportURL, url)
    }

    @MainActor func testScenarioReplaysAreDeterministicAndRetainLogging() async {
        for scenario in SimulationScenario.allCases {
            let a = SimulationController(automaticallyTicks: false), b = SimulationController(automaticallyTicks: false)
            a.startLogging(); a.startScenario(scenario); b.startScenario(scenario)
            var peakSpeed = 0.0
            for _ in 0..<Int(scenario.duration * 5) {
                a.advance(seconds: 0.2)
                b.advance(seconds: 0.05); b.advance(seconds: 0.15)
                peakSpeed = max(peakSpeed, a.vehicle.speedKmh)
                XCTAssertEqual(a.engine.rpm, b.engine.rpm, accuracy: 1e-7)
                XCTAssertEqual(a.vehicle.speedKmh, b.vehicle.speedKmh, accuracy: 1e-7)
                XCTAssertEqual(a.vehicle.estimatedThrottle, b.vehicle.estimatedThrottle)
                XCTAssertEqual(a.transmission.currentGear, b.transmission.currentGear)
                XCTAssertTrue((1...8).contains(a.transmission.currentGear))
                XCTAssertTrue((750...6700).contains(a.engine.rpm))
            }
            XCTAssertFalse(a.isDemoRunning, scenario.rawValue)
            XCTAssertTrue(a.vehicle.isStopped)
            XCTAssertEqual(a.engine.rpm, 750, accuracy: 1)
            XCTAssertGreaterThan(peakSpeed, 15)
            XCTAssertEqual(a.logger.records.count, Int(scenario.duration * 5))
            XCTAssertTrue(a.logger.isLogging)
            a.stopLogging()
        }
    }

    @MainActor func testTimelineIncludesShiftsLiftAndLoggingBackgroundStop() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.applyPreset(.sport)
        controller.startLogging(); controller.startScenario(.liftDownshift)
        controller.advance(seconds: SimulationScenario.liftDownshift.duration)
        XCTAssertTrue(controller.events.contains { $0.message.hasPrefix("Upshift") })
        XCTAssertTrue(controller.events.contains { $0.message.hasPrefix("Downshift") })
        XCTAssertTrue(controller.events.contains { $0.message == "Throttle lift detected" })
        XCTAssertTrue(controller.logger.records.contains { $0.shiftType == .upshift })
        controller.setForeground(false)
        XCTAssertFalse(controller.logger.isLogging)
        XCTAssertGreaterThan(controller.logger.records.count, 100)
    }
}

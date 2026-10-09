import XCTest
import Observation
@testable import VirtualV8

final class SimulationControllerTests: XCTestCase {
    @MainActor func testProfileIDsUsedBySelectionRowsUpdateAndPersistAllProfiles() async {
        let domain = "VirtualV8.profile-picker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let controller = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        for profile in EngineProfile.available {
            XCTAssertTrue(controller.selectProfile(id: profile.id))
            XCTAssertEqual(controller.profile.id, profile.id)
            XCTAssertEqual(controller.audio.profile.id, profile.id)
            let restored = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
            XCTAssertEqual(restored.profile.id, profile.id)
        }
        let selected = controller.profile
        XCTAssertFalse(controller.selectProfile(id: "missing-profile"))
        XCTAssertEqual(controller.profile, selected)
        controller.startEngine()
        XCTAssertFalse(controller.selectProfile(id: EngineProfile.americanV8.id))
        XCTAssertEqual(controller.profile, selected)
        controller.stopEngine()
        XCTAssertTrue(controller.selectProfile(id: EngineProfile.americanV8.id))
        XCTAssertEqual(controller.profile, .americanV8)
    }

    @MainActor func testClassicProfilePersistenceSwitchingAndIdle() async {
        let domain = "VirtualV8.classics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let controller = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        for profile in EngineProfile.classics {
            controller.selectProfile(profile)
            let restored = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
            XCTAssertEqual(restored.profile, profile)
            XCTAssertEqual(restored.audio.profile, profile)
            controller.startEngine(); controller.advance(seconds: 3)
            XCTAssertEqual(controller.engine.rpm, profile.idleRPM, accuracy: 2)
            controller.selectProfile(.americanV8)
            XCTAssertEqual(controller.profile, profile, "Running engine must block profile switching")
            controller.stopEngine()
        }
        controller.selectProfile(.americanV8); controller.startEngine(); controller.advance(seconds: 3)
        XCTAssertEqual(controller.engine.rpm, 750, accuracy: 2)
    }

    @MainActor func testBMWScenarioReachesHighRevRangeAndReturnsToIdle() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.selectProfile(.bmwS65)
        controller.drivingMode = .track
        controller.startDemo()
        var maximumRPM = 0.0; var upshifts = 0; var downshifts = 0; var wasShifting = false
        for _ in 0..<60 * 44 {
            controller.advance(seconds: 1.0 / 60)
            maximumRPM = max(maximumRPM, controller.engine.rpm)
            if controller.transmission.isShifting && !wasShifting {
                if controller.transmission.shiftType == .upshift { upshifts += 1 }
                if controller.transmission.shiftType == .downshift { downshifts += 1 }
            }
            wasShifting = controller.transmission.isShifting
            XCTAssertTrue((1...8).contains(controller.transmission.currentGear))
            XCTAssertLessThanOrEqual(controller.engine.rpm, controller.profile.hardLimiterRPM)
        }
        XCTAssertGreaterThan(maximumRPM, 7500, "Track shifts should allow the S65's high-RPM sound bands")
        XCTAssertGreaterThanOrEqual(upshifts, 2); XCTAssertGreaterThanOrEqual(downshifts, 2)
        XCTAssertEqual(controller.operatingMode, .idle)
        XCTAssertEqual(controller.engine.rpm, 800, accuracy: 2)
    }

    @MainActor func testEngineProfileSelectionPersistenceAndRunningGuard() async {
        let domain = "VirtualV8.profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let controller = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        XCTAssertEqual(controller.profile, .americanV8)
        controller.selectProfile(.bmwS65)
        XCTAssertEqual(controller.audio.profile, .bmwS65)
        controller.startEngine()
        controller.advance(seconds: 3)
        XCTAssertEqual(controller.engine.rpm, 800, accuracy: 2)
        controller.selectProfile(.americanV8)
        XCTAssertEqual(controller.profile, .bmwS65, "Running engine must keep its audio/profile together")
        let restored = SimulationController(automaticallyTicks: false, settingsDefaults: defaults)
        XCTAssertEqual(restored.profile, .bmwS65)
        controller.stopEngine()
        controller.selectProfile(.americanV8)
        controller.startEngine()
        controller.advance(seconds: 3)
        XCTAssertEqual(controller.engine.rpm, 750, accuracy: 2)
        XCTAssertEqual(controller.audio.profile, .americanV8)
    }

    @MainActor func testScreenAwakePolicyTracksEngineInputAndForeground() async {
        let controller = SimulationController(automaticallyTicks: false)
        XCTAssertFalse(controller.shouldKeepScreenAwake)
        controller.startEngine()
        XCTAssertFalse(controller.shouldKeepScreenAwake, "Simulation retains normal auto-lock")
        controller.selectInputMode(.realDrive)
        XCTAssertTrue(controller.shouldKeepScreenAwake)
        controller.setForeground(false)
        XCTAssertFalse(controller.shouldKeepScreenAwake)
        controller.setForeground(true)
        XCTAssertTrue(controller.shouldKeepScreenAwake)
        controller.stopEngine()
        XCTAssertFalse(controller.shouldKeepScreenAwake)
        controller.startEngine()
        XCTAssertTrue(controller.shouldKeepScreenAwake)
        controller.selectInputMode(.simulation)
        XCTAssertFalse(controller.shouldKeepScreenAwake)
    }

    @MainActor func testStartStopAndManualInputs() async {
        let controller = SimulationController(automaticallyTicks: false)
        XCTAssertEqual(controller.operatingMode, .off)
        controller.setThrottle(0.5)
        controller.setBrake(0.25)
        controller.setSpeed(80)
        XCTAssertEqual(controller.vehicle.estimatedThrottle, 0.5)
        XCTAssertEqual(controller.vehicle.brakeInput, 0.25)
        XCTAssertEqual(controller.vehicle.speedKmh, 80)
        XCTAssertEqual(controller.engine.rpm, 0)
        controller.startEngine()
        XCTAssertEqual(controller.operatingMode, .starting)
        tick(controller, seconds: 2)
        XCTAssertTrue(controller.engine.isRunning)
        XCTAssertGreaterThan(controller.engine.rpm, 800)
        XCTAssertEqual(controller.engine.throttle, 0.5, accuracy: 0.001)
        controller.stopEngine()
        XCTAssertFalse(controller.engine.isRunning)
        XCTAssertEqual(controller.engine.rpm, 0)
        XCTAssertEqual(controller.vehicle.speedKmh, 0)
        XCTAssertEqual(controller.transmission.currentGear, 1)
        XCTAssertEqual(controller.operatingMode, .off)
    }

    @MainActor func testInputBoundsAndLimiter() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.setThrottle(2)
        controller.setBrake(-1)
        controller.setSpeed(500)
        XCTAssertEqual(controller.vehicle.estimatedThrottle, 1)
        XCTAssertEqual(controller.vehicle.brakeInput, 0)
        XCTAssertEqual(controller.vehicle.speedKmh, 250)
        controller.drivingMode = .track
        controller.startEngine()
        controller.setSpeed(0)
        tick(controller, seconds: 4)
        XCTAssertTrue(controller.engine.isOnLimiter)
        XCTAssertLessThanOrEqual(controller.engine.rpm, controller.profile.hardLimiterRPM)
        XCTAssertGreaterThan(controller.engine.normalizedRPM, 0.9)
        controller.setThrottle(.nan)
        XCTAssertEqual(controller.vehicle.estimatedThrottle, 0)
    }

    @MainActor func testCompleteDemoIncludesUpshiftsDownshiftsAndIdle() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.startDemo()
        var highestSpeed = 0.0
        var gears = Set<Int>()
        var modes = Set<EngineOperatingMode>()
        var shifts = Set<ShiftType>()
        var sawBraking = false
        for _ in 0..<900 {
            controller.advance(seconds: 0.05)
            highestSpeed = max(highestSpeed, controller.vehicle.speedKmh)
            gears.insert(controller.transmission.currentGear)
            modes.insert(controller.operatingMode)
            shifts.insert(controller.transmission.shiftType)
            sawBraking = sawBraking || controller.vehicle.brakeInput > 0
        }
        XCTAssertEqual(highestSpeed, 160, accuracy: 0.1)
        XCTAssertTrue(Set([1, 2, 3, 4, 5]).isSubset(of: gears))
        XCTAssertTrue(shifts.contains(.upshift))
        XCTAssertTrue(shifts.contains(.downshift))
        XCTAssertTrue(modes.contains(.starting))
        XCTAssertTrue(modes.contains(.overrun))
        XCTAssertTrue(modes.contains(.revMatch))
        XCTAssertTrue(sawBraking)
        XCTAssertFalse(controller.isDemoRunning)
        XCTAssertTrue(controller.vehicle.isStopped)
        XCTAssertTrue(controller.engine.isRunning)
        XCTAssertEqual(controller.engine.rpm, 750, accuracy: 1)
        XCTAssertEqual(controller.transmission.currentGear, 1)
        XCTAssertEqual(controller.operatingMode, .idle)
    }

    @MainActor func testManualInputCancelsDemoAndStopPreventsRestart() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.startDemo()
        tick(controller, seconds: 5)
        controller.setThrottle(0.4)
        XCTAssertFalse(controller.isDemoRunning)
        tick(controller, seconds: 1)
        XCTAssertEqual(controller.vehicle.estimatedThrottle, 0.4)
        controller.startDemo()
        controller.stopEngine()
        tick(controller, seconds: 40)
        XCTAssertFalse(controller.isDemoRunning)
        XCTAssertFalse(controller.engine.isRunning)
        XCTAssertEqual(controller.operatingMode, .off)
    }

    @MainActor func testLiveTimerAdvancesDemo() async throws {
        let controller = SimulationController(audioOutput: .disabled)
        controller.startDemo()
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertGreaterThan(controller.demoElapsed, 0.8)
        XCTAssertEqual(controller.operatingMode, .idle)
        controller.stopEngine()
    }

    @MainActor func testSliderInputsPublishChangesForViews() async {
        let controller = SimulationController(automaticallyTicks: false)
        final class Notification: @unchecked Sendable { var received = false }
        let notification = Notification()
        withObservationTracking {
            _ = controller.vehicle.estimatedThrottle
            _ = controller.vehicle.speedKmh
            _ = controller.vehicle.brakeInput
        } onChange: {
            notification.received = true
        }
        controller.setThrottle(0.65)
        XCTAssertTrue(notification.received)
        XCTAssertEqual(controller.vehicle.estimatedThrottle, 0.65)
        controller.setSpeed(90)
        controller.setBrake(0.4)
        XCTAssertEqual(controller.vehicle.speedKmh, 90)
        XCTAssertEqual(controller.vehicle.brakeInput, 0.4)
    }

    @MainActor func testDemoInEveryDrivingModeIncludesHighRPMAndSeveralShifts() async {
        for mode in DrivingMode.allCases {
            let controller = SimulationController(automaticallyTicks: false)
            controller.drivingMode = mode
            controller.startDemo()
            var maximumRPM = 0.0
            var upshifts = 0
            var downshifts = 0
            var shifting = false
            for _ in 0..<Int((DemoSequence.duration + 3) * 60) {
                controller.advance(seconds: 1.0 / 60)
                maximumRPM = max(maximumRPM, controller.engine.rpm)
                if !shifting && controller.transmission.isShifting {
                    if controller.transmission.shiftType == .upshift { upshifts += 1 }
                    else { downshifts += 1 }
                }
                shifting = controller.transmission.isShifting
            }
            let expectedHighRPM = mode == .sport ? 4800.0 : mode == .track ? 6200 : 5500
            XCTAssertGreaterThan(maximumRPM, expectedHighRPM, mode.rawValue)
            XCTAssertGreaterThanOrEqual(upshifts, 3, mode.rawValue)
            XCTAssertGreaterThanOrEqual(downshifts, 3, mode.rawValue)
            XCTAssertEqual(controller.transmission.currentGear, 1, mode.rawValue)
            XCTAssertEqual(controller.engine.rpm, 750, accuracy: 1, mode.rawValue)
            XCTAssertEqual(controller.operatingMode, .idle, mode.rawValue)
        }
    }

    @MainActor func testSliderChangesDoNotInstantlyJumpRPM() async {
        let controller = SimulationController(automaticallyTicks: false)
        controller.startEngine()
        controller.advance(seconds: 3)
        let idle = controller.engine.rpm
        controller.setSpeed(250)
        controller.setThrottle(1)
        XCTAssertEqual(controller.engine.rpm, idle)
        controller.advance(seconds: SimulationController.fixedDeltaTime)
        XCTAssertGreaterThan(controller.engine.rpm, idle)
        XCTAssertLessThan(controller.engine.rpm - idle, 350)
        XCTAssertLessThan(controller.engine.rpm, controller.engine.targetRPM)
    }

    @MainActor func testFixedStepIsDeterministicAcrossDifferentFrameDurations() async {
        let small = SimulationController(automaticallyTicks: false)
        let large = SimulationController(automaticallyTicks: false)
        small.startDemo()
        large.startDemo()
        for _ in 0..<600 { small.advance(seconds: 1.0 / 60) }
        for _ in 0..<100 { large.advance(seconds: 0.1) }
        XCTAssertEqual(small.engine.rpm, large.engine.rpm, accuracy: 0.0001)
        XCTAssertEqual(small.engine.targetRPM, large.engine.targetRPM, accuracy: 0.0001)
        XCTAssertEqual(small.transmission.currentGear, large.transmission.currentGear)
        XCTAssertEqual(small.transmission.shiftProgress, large.transmission.shiftProgress, accuracy: 0.0001)
        XCTAssertEqual(small.demoElapsed, large.demoElapsed, accuracy: 0.0001)
    }

    @MainActor private func tick(_ controller: SimulationController, seconds: Double) {
        for _ in 0..<Int(seconds / 0.05) { controller.advance(seconds: 0.05) }
    }
}

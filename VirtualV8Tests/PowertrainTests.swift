import XCTest
@testable import VirtualV8

final class PowertrainTests: XCTestCase {
    private let dt = 1.0 / 60.0

    func testEngineStartupAndIdleNeverFallBelow750() {
        var engine = VirtualEngine()
        let transmission = VirtualTransmission()
        engine.start()
        var sawFlare = false
        for _ in 0..<300 {
            engine.update(deltaTime: dt, vehicle: VehicleState(), transmission: transmission, drivingMode: .comfort)
            XCTAssertGreaterThanOrEqual(engine.state.rpm, 750)
            sawFlare = sawFlare || engine.state.rpm > 900
        }
        XCTAssertTrue(sawFlare)
        XCTAssertEqual(engine.state.rpm, 750, accuracy: 0.1)
        XCTAssertEqual(engine.operatingMode, .idle)
    }

    func testRPMRisesAndFallsWithInertiaAndLoad() {
        var engine = VirtualEngine()
        let transmission = VirtualTransmission()
        var vehicle = VehicleState()
        engine.start()
        for _ in 0..<180 { engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .sport) }
        let idle = engine.state.rpm
        vehicle.estimatedThrottle = 0.8
        engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .sport)
        XCTAssertGreaterThan(engine.state.rpm, idle)
        XCTAssertLessThan(engine.state.rpm, engine.state.targetRPM)
        XCTAssertLessThan(engine.state.rpm - idle, 300)
        for _ in 0..<180 { engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .sport) }
        let highRPM = engine.state.rpm
        XCTAssertGreaterThan(highRPM, 5000)
        XCTAssertGreaterThan(engine.state.load, 0.2)
        vehicle.estimatedThrottle = 0
        engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .sport)
        XCTAssertGreaterThan(engine.state.rpm, 750)
        for _ in 0..<300 { engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .sport) }
        XCTAssertLessThan(engine.state.rpm, highRPM)
        XCTAssertEqual(engine.state.rpm, 750, accuracy: 1)
        XCTAssertLessThan(engine.state.load, 0.01)
    }

    func testRPMLimitsAndOverrun() {
        var engine = VirtualEngine()
        let transmission = VirtualTransmission()
        var vehicle = VehicleState()
        vehicle.estimatedThrottle = 1
        engine.start()
        for _ in 0..<600 {
            engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .track)
            XCTAssertGreaterThanOrEqual(engine.state.rpm, 750)
            XCTAssertLessThanOrEqual(engine.state.rpm, 6700)
        }
        XCTAssertTrue(engine.state.isOnLimiter)
        XCTAssertEqual(engine.operatingMode, .limiter)
        XCTAssertLessThanOrEqual(engine.state.targetRPM, 6400)
        vehicle.speedKmh = 25
        vehicle.estimatedThrottle = 0
        for _ in 0..<240 { engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: .track) }
        XCTAssertEqual(engine.operatingMode, .overrun)
        XCTAssertGreaterThan(engine.state.rpm, 750)
        engine.stop()
        XCTAssertEqual(engine.state.rpm, 0)
        XCTAssertEqual(engine.operatingMode, .off)
    }

    func testRPMFormulaAndEightRatios() {
        let transmission = VirtualTransmission()
        XCTAssertEqual(VirtualTransmission.gearRatios, [4.56, 2.97, 2.08, 1.69, 1.27, 1, 0.85, 0.65])
        for gear in 1...8 {
            let expected = 100.0 / 3.6 / 2.10 * 60 * VirtualTransmission.gearRatios[gear - 1] * 3.55
            XCTAssertEqual(transmission.rpm(forSpeedKmh: 100, gear: gear), expected, accuracy: 0.001)
        }
        XCTAssertEqual(transmission.rpm(forSpeedKmh: -5, gear: 0), 0)
        XCTAssertEqual(transmission.ratio(for: 100), 0.65)
    }

    func testTimedUpshiftChangesRPMBeforeGearCommits() {
        var rig = Rig(mode: .track)
        rig.vehicle.estimatedThrottle = 1
        var sawShift = false
        var startRPM = 0.0
        var lowestDuringShift = Double.infinity
        for frame in 0..<1800 {
            rig.vehicle.speedKmh = min(90, Double(frame) * dt * 5)
            let before = rig.transmission.state
            rig.step()
            let after = rig.transmission.state
            if after.isShifting && after.currentGear == 2 && after.targetGear == 3 {
                if !sawShift {
                    sawShift = true
                    startRPM = rig.transmission.shiftStartRPM
                    XCTAssertEqual(after.currentGear, before.currentGear)
                    XCTAssertTrue((0.15...0.45).contains(rig.transmission.shiftDuration))
                }
                XCTAssertEqual(after.currentGear, 2)
                XCTAssertGreaterThan(rig.engine.state.targetRPM, 3500)
                XCTAssertLessThan(rig.engine.state.targetRPM, startRPM)
                lowestDuringShift = min(lowestDuringShift, rig.engine.state.rpm)
                XCTAssertEqual(rig.engine.operatingMode, .shift)
            } else if sawShift && after.currentGear == 3 { break }
        }
        XCTAssertTrue(sawShift)
        XCTAssertEqual(rig.transmission.state.currentGear, 3)
        XCTAssertGreaterThan(startRPM, 5900)
        XCTAssertLessThan(lowestDuringShift, startRPM - 1000)
        XCTAssertGreaterThan(lowestDuringShift, 3500)
    }

    func testDownshiftFlareAndAggressiveRevMatch() {
        var rig = Rig(mode: .sport)
        var foundFlare = false
        var foundDownshift = false
        for frame in 0..<3000 {
            let time = Double(frame) * dt
            rig.vehicle.speedKmh = time < 20 ? min(120, time * 6) : max(0, 120 - (time - 20) * 6)
            rig.vehicle.estimatedThrottle = time < 20 ? 0.45 : 0
            rig.vehicle.brakeInput = time < 20 ? 0 : 0.7
            rig.step()
            if rig.transmission.state.isShifting && rig.transmission.state.shiftType == .downshift {
                foundDownshift = true
                XCTAssertEqual(rig.engine.operatingMode, .revMatch)
                if rig.transmission.shiftStartSpeed > 20 {
                    foundFlare = foundFlare || rig.engine.state.rpm > rig.transmission.shiftStartRPM + 150
                }
            }
        }
        XCTAssertTrue(foundDownshift)
        XCTAssertTrue(foundFlare)
        XCTAssertEqual(rig.transmission.state.currentGear, 1)
    }

    func testHighThrottleDelaysUpshiftAndLowThrottleShiftsEarlier() {
        func firstUpshift(throttle: Double, mode: DrivingMode) -> Double {
            var rig = Rig(mode: mode)
            rig.vehicle.estimatedThrottle = throttle
            for frame in 0..<2400 {
                rig.vehicle.speedKmh = Double(frame) * dt * 3
                rig.step()
                if rig.transmission.state.isShifting { return rig.transmission.shiftStartRPM }
            }
            XCTFail("No upshift")
            return 0
        }
        let light = firstUpshift(throttle: 0.15, mode: .comfort)
        let heavy = firstUpshift(throttle: 0.95, mode: .comfort)
        XCTAssertTrue((2200...3000).contains(light))
        XCTAssertGreaterThan(heavy, light + 2000)
        let sport = firstUpshift(throttle: 0.5, mode: .sport)
        XCTAssertTrue((3500...5000).contains(sport))
        let track = firstUpshift(throttle: 1, mode: .track)
        XCTAssertGreaterThan(track, 6200)
    }

    func testNoGearHuntingAtSteadySpeedAndBoundaryNoise() {
        var rig = Rig(mode: .comfort)
        rig.vehicle.estimatedThrottle = 0.2
        for frame in 0..<1200 {
            rig.vehicle.speedKmh = min(60, Double(frame) * dt * 6)
            rig.step()
        }
        let settledGear = rig.transmission.state.currentGear
        var shiftCount = 0
        for frame in 0..<1800 {
            rig.vehicle.speedKmh = 60 + sin(Double(frame) * dt * 4) * 0.8
            rig.step()
            if rig.transmission.state.isShifting { shiftCount += 1 }
            XCTAssertEqual(rig.transmission.state.currentGear, settledGear)
        }
        XCTAssertEqual(shiftCount, 0)
    }

    func testGearRangeCanReachEightAndReturnToOne() {
        var rig = Rig(mode: .comfort)
        rig.vehicle.estimatedThrottle = 0.15
        var gears = Set<Int>()
        for frame in 0..<5400 {
            let time = Double(frame) * dt
            rig.vehicle.speedKmh = time < 45 ? min(250, time * 8) : max(0, 250 - (time - 45) * 8)
            rig.step()
            gears.insert(rig.transmission.state.currentGear)
            XCTAssertTrue((1...8).contains(rig.transmission.state.currentGear))
            XCTAssertTrue((1...8).contains(rig.transmission.state.targetGear))
        }
        XCTAssertEqual(gears, Set(1...8))
        XCTAssertEqual(rig.transmission.state.currentGear, 1)
    }

    func testKickdownAndCooldown() {
        var rig = Rig(mode: .sport)
        rig.vehicle.estimatedThrottle = 0.1
        for frame in 0..<2400 {
            rig.vehicle.speedKmh = min(80, Double(frame) * dt * 6)
            rig.step()
        }
        let cruisingGear = rig.transmission.state.currentGear
        XCTAssertGreaterThan(cruisingGear, 2)
        rig.vehicle.estimatedThrottle = 1
        rig.step()
        XCTAssertTrue(rig.transmission.state.isShifting)
        XCTAssertLessThan(rig.transmission.state.targetGear, cruisingGear)
        XCTAssertEqual(rig.engine.operatingMode, .revMatch)
        while rig.transmission.state.isShifting { rig.step() }
        for _ in 0..<30 {
            rig.step()
            XCTAssertFalse(rig.transmission.state.isShifting)
        }
    }

    func testKickdownRequestDuringCooldownIsRetained() {
        var rig = Rig(mode: .sport)
        rig.vehicle.speedKmh = 30
        rig.vehicle.estimatedThrottle = 0.1
        for _ in 0..<300 {
            rig.step()
            if rig.transmission.state.currentGear == 2 && !rig.transmission.state.isShifting { break }
        }
        XCTAssertEqual(rig.transmission.state.currentGear, 2)
        rig.vehicle.estimatedThrottle = 1
        rig.step()
        XCTAssertFalse(rig.transmission.state.isShifting)
        var kickdownOccurred = false
        for _ in 0..<240 {
            rig.step()
            if rig.transmission.state.isShifting && rig.transmission.state.shiftType == .downshift {
                kickdownOccurred = true
                XCTAssertEqual(rig.transmission.state.targetGear, 1)
                break
            }
        }
        XCTAssertTrue(kickdownOccurred, "A pedal request during cooldown must execute once it is safe")
    }

    func testExponentialResponseIsIndependentOfFrameSize() {
        // After startup at fixed speed/load the RPM target is constant.
        func rpm(step: Double) -> Double {
            var engine = VirtualEngine()
            let transmission = VirtualTransmission()
            var vehicle = VehicleState()
            engine.start()
            for _ in 0..<Int(2 / step) {
                engine.update(deltaTime: step, vehicle: vehicle, transmission: transmission, drivingMode: .comfort)
            }
            vehicle.speedKmh = 30
            for _ in 0..<Int(2 / step) {
                engine.update(deltaTime: step, vehicle: vehicle, transmission: transmission, drivingMode: .comfort)
            }
            return engine.state.rpm
        }
        XCTAssertEqual(rpm(step: 1.0 / 60), rpm(step: 1.0 / 120), accuracy: 1)
    }

    private struct Rig {
        var engine = VirtualEngine()
        var transmission = VirtualTransmission()
        var vehicle = VehicleState()
        let mode: DrivingMode
        init(mode: DrivingMode) { self.mode = mode; engine.start() }
        mutating func step() {
            let dt = 1.0 / 60.0
            if engine.operatingMode != .starting {
                transmission.update(deltaTime: dt, vehicle: vehicle, engine: engine.state,
                                    mode: mode, configuration: .americanV8)
            }
            engine.update(deltaTime: dt, vehicle: vehicle, transmission: transmission, drivingMode: mode)
        }
    }
}

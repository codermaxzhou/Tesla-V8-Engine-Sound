import XCTest
import AVFoundation
@testable import VirtualV8

final class AudioTests: XCTestCase {
    func testMaximumBackfireProducesOneIrregularBurstPerDownshift() {
        for drivingMode in DrivingMode.allCases {
            var mix = AudioMixModel(seed: 0x62A8)
            var engine = EngineState(); engine.isRunning = true; engine.rpm = 1200; engine.targetRPM = 2500
            var transmission = TransmissionState()
            var tuning = AudioTuning(); tuning.backfireAmount = 1
            var burstCounts = Array(repeating: 0, count: 12)
            var popFrames: [Int] = []
            for frame in 0..<1440 {
                // Twelve separate shifts, with long isShifting windows to catch retriggers.
                transmission.isShifting = frame % 120 < 24
                transmission.shiftType = .downshift
                let events = mix.update(engine: engine, vehicle: VehicleState(), transmission: transmission,
                    mode: transmission.isShifting ? .revMatch : .overrun,
                    drivingMode: drivingMode, tuning: tuning, deltaTime: 1.0 / 60)
                let pops = events.filter { $0.layer == .backfire }
                burstCounts[frame / 120] += pops.count
                if !pops.isEmpty { popFrames.append(frame) }
                XCTAssertTrue(pops.allSatisfy { $0.gain > 0 && $0.gain <= 1 })
            }
            XCTAssertTrue(burstCounts.allSatisfy { (2...5).contains($0) }, "Every downshift gets a bounded burst at maximum tuning")
            XCTAssertGreaterThan(Set(burstCounts).count, 1, "Pop count must vary between shifts")
            let intervals = zip(popFrames, popFrames.dropFirst()).map { $1 - $0 }.filter { $0 < 60 }
            XCTAssertGreaterThan(Set(intervals).count, 1, "Burst spacing must be irregular")
        }
    }

    func testDownshiftCountRandomDrawCoversRangeAndTuningLimits() {
        let backfire = BackfireController(configuration: .forMode(.sport))
        let counts = stride(from: 0.0, through: 1, by: 0.05).map {
            backfire.downshiftBurstCount(rpm: 4000, timeSinceLastBurst: 1,
                amount: 1, roll: 0, burstRoll: $0)
        }
        XCTAssertEqual(Set(counts), Set(2...5))
        for amount in [0.1, 0.3, 0.5, 0.75, 1.0] {
            let count = backfire.downshiftBurstCount(rpm: 4000, timeSinceLastBurst: 1,
                amount: amount, roll: 0, burstRoll: 1)
            XCTAssertLessThanOrEqual(count, Int((1 + 4 * amount).rounded()))
        }
    }

    func testDownshiftBackfireCooldownIdleAndZeroAmount() {
        let backfire = BackfireController(configuration: .forMode(.track))
        XCTAssertEqual(backfire.downshiftBurstCount(rpm: 4000, timeSinceLastBurst: 1, amount: 1, roll: 0.99, burstRoll: 0.99), 5)
        XCTAssertEqual(backfire.downshiftBurstCount(rpm: 4000, timeSinceLastBurst: 0.1, amount: 1, roll: 0, burstRoll: 0.99), 0)
        XCTAssertEqual(backfire.downshiftBurstCount(rpm: 750, timeSinceLastBurst: 1, amount: 1, roll: 0, burstRoll: 0.99), 0)
        XCTAssertEqual(backfire.downshiftBurstCount(rpm: 4000, timeSinceLastBurst: 1, amount: 0, roll: 0, burstRoll: 0.99), 0)
        XCTAssertEqual(backfire.downshiftBurstCount(rpm: 4000, timeSinceLastBurst: 1, amount: 0.5, roll: 0.99, burstRoll: 0.99), 0)
        for mute in [false, true] {
            var mix = AudioMixModel(seed: 0x62A8)
            var engine = EngineState(); engine.isRunning = true; engine.rpm = 4000
            var transmission = TransmissionState(); transmission.isShifting = true; transmission.shiftType = .downshift
            var tuning = AudioTuning(); tuning.backfireAmount = 1
            _ = mix.update(engine: engine, vehicle: VehicleState(), transmission: transmission,
                mode: .revMatch, drivingMode: .track, tuning: tuning, deltaTime: 1.0 / 60)
            if mute { tuning.isMuted = true } else { tuning.backfireAmount = 0 }
            for _ in 0..<60 {
                let events = mix.update(engine: engine, vehicle: VehicleState(), transmission: transmission,
                    mode: .revMatch, drivingMode: .track, tuning: tuning, deltaTime: 1.0 / 60)
                XCTAssertFalse(events.contains { $0.layer == .backfire }, "Turning off pops cancels queued bursts")
            }
        }
    }

    @MainActor func testDownshiftPopsAreAudibleInRenderedAudioAndHaveHeadroom() throws {
        func render(amount: Double) throws -> (peak: Float, rms: Double, count: Int) {
            let audio = EngineAudioEngine(outputMode: .offline, randomSeed: 0x62A8)
            defer { audio.shutdown() }
            audio.tuning.masterVolume = 1; audio.tuning.engineVolume = 1
            audio.tuning.exhaustVolume = 1; audio.tuning.backfireAmount = amount
            var engine = EngineState(); engine.isRunning = true; engine.rpm = 4000
            var transmission = TransmissionState()
            var peak: Float = 0; var squared = 0.0; var samples = 0
            let dt = 512.0 / 48000
            for frame in 0..<200 {
                transmission.isShifting = frame >= 100 && frame < 125
                transmission.shiftType = .downshift
                audio.update(engine: engine, vehicle: VehicleState(), transmission: transmission,
                    mode: transmission.isShifting ? .revMatch : .overrun,
                    drivingMode: .sport, deltaTime: dt)
                let buffer = try audio.render(frameCount: 512)
                for index in 0..<Int(buffer.frameLength) {
                    let value = buffer.floatChannelData![0][index]
                    XCTAssertTrue(value.isFinite)
                    peak = max(peak, abs(value))
                    if frame >= 100 { squared += Double(value) * Double(value); samples += 1 }
                }
            }
            XCTAssertNil(audio.errorMessage)
            XCTAssertEqual(audio.startCount, 1, "Bursts must not restart the looping audio graph")
            return (peak, sqrt(squared / Double(samples)), audio.transientCount)
        }
        let quiet = try render(amount: 0)
        let pops = try render(amount: 1)
        XCTAssertTrue((2...5).contains(pops.count - quiet.count))
        // A two-pop burst has less total energy than five pops; peak contrast
        // below checks presence, while RMS checks that even short bursts add energy.
        XCTAssertGreaterThan(pops.rms, quiet.rms * 1.1, "Short bursts must add energy above continuous overrun")
        XCTAssertGreaterThan(pops.peak, quiet.peak * 1.25)
        XCTAssertLessThan(pops.peak, 0.95, "Maximum tuning must retain output headroom")
    }

    func testCrossfadesCoverRPMRangeWithoutHardSwitches() {
        for rpm in stride(from: 700.0, through: 6800, by: 5) {
            let weights = AudioMixModel.rpmWeights(rpm)
            XCTAssertEqual(weights.values.reduce(0, +), 1, accuracy: 0.000001)
            for layer in [AudioLayer.idle, .lowRPM, .midRPM, .highRPM] {
                XCTAssertTrue((0...1).contains(weights[layer, default: 0]))
                XCTAssertLessThan(abs(weights[layer, default: 0] - AudioMixModel.rpmWeights(rpm + 1)[layer, default: 0]), 0.01)
            }
        }
        XCTAssertEqual(AudioMixModel.rpmWeights(750)[.idle], 1)
        XCTAssertEqual(AudioMixModel.rpmWeights(3500)[.midRPM], 1)
        XCTAssertEqual(AudioMixModel.rpmWeights(6500)[.highRPM], 1)
    }

    func testLoadIntakeOverrunAndShiftDuckAreIndependentOfRPM() {
        var mix = AudioMixModel(seed: 0x62A8)
        var engine = EngineState()
        engine.isRunning = true; engine.rpm = 3500; engine.load = 0.1
        var vehicle = VehicleState(); vehicle.estimatedThrottle = 0.1
        var transmission = TransmissionState()
        func update(_ count: Int, mode: EngineOperatingMode = .cruise) {
            for _ in 0..<count {
                _ = mix.update(engine: engine, vehicle: vehicle, transmission: transmission, mode: mode,
                               drivingMode: .sport, tuning: AudioTuning(), deltaTime: 1.0 / 60)
            }
        }
        update(60)
        let quietLoad = mix.gains[.highLoad, default: 0]
        let quietIntake = mix.gains[.intake, default: 0]
        engine.load = 1; vehicle.estimatedThrottle = 1
        update(60)
        XCTAssertGreaterThan(mix.gains[.highLoad, default: 0], quietLoad * 5)
        XCTAssertGreaterThan(mix.gains[.intake, default: 0], quietIntake * 5)
        let fullLoad = mix.gains[.highLoad, default: 0]
        transmission.isShifting = true; transmission.shiftType = .upshift
        update(20, mode: .shift)
        XCTAssertLessThan(mix.gains[.highLoad, default: 0], fullLoad * 0.4)
        transmission.isShifting = false
        update(40)
        XCTAssertGreaterThan(mix.gains[.highLoad, default: 0], fullLoad * 0.95)
        vehicle.estimatedThrottle = 0; engine.load = 0
        update(40, mode: .overrun)
        XCTAssertGreaterThan(mix.gains[.overrun, default: 0], 0.1)
    }

    func testBackfireProbabilityCooldownAndBurstBounds() {
        let controller = BackfireController(configuration: .init(backfireProbability: 1, minimumInterval: 2, maximumBurstCount: 2))
        func burst(previous: Double = 0.9, rpm: Double = 4000, interval: Double = 3, amount: Double = 1) -> Int {
            controller.burstCount(currentThrottle: 0, previousThrottle: previous, rpm: rpm, engineMode: .overrun,
                                 deceleration: -1, timeSinceLastBackfire: interval, amount: amount, roll: 0.1, burstRoll: 0.99)
        }
        XCTAssertEqual(burst(), 2)
        XCTAssertEqual(burst(previous: 0.4), 0)
        XCTAssertEqual(burst(rpm: 2000), 0)
        XCTAssertEqual(burst(interval: 1), 0)
        XCTAssertEqual(burst(amount: 0), 0)
        let comfort = BackfireController(configuration: .forMode(.comfort))
        XCTAssertEqual(comfort.burstCount(currentThrottle: 0, previousThrottle: 1, rpm: 4000, engineMode: .overrun,
                                        deceleration: -1, timeSinceLastBackfire: 10, amount: 1, roll: 0.02, burstRoll: 0), 0)
    }

    func testStationaryThrottleLiftCanProduceOverrunAndOccasionalBackfire() {
        var mix = AudioMixModel(seed: 0x62A8)
        var engine = EngineState(); engine.isRunning = true; engine.rpm = 4500
        var vehicle = VehicleState(); vehicle.estimatedThrottle = 1
        for _ in 0..<30 {
            _ = mix.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(), mode: .fullLoad,
                           drivingMode: .track, tuning: AudioTuning(), deltaTime: 1.0 / 60)
        }
        vehicle.estimatedThrottle = 0
        for _ in 0..<30 {
            _ = mix.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(), mode: .idle,
                           drivingMode: .track, tuning: AudioTuning(), deltaTime: 1.0 / 60)
        }
        XCTAssertGreaterThan(mix.gains[.overrun, default: 0], 0.1)
        let backfire = BackfireController(configuration: .forMode(.track))
        XCTAssertGreaterThan(backfire.burstCount(currentThrottle: 0, previousThrottle: 1, rpm: 4500,
                           engineMode: .idle, deceleration: 0, timeSinceLastBackfire: 5, amount: 1,
                           roll: 0.1, burstRoll: 0.7), 0)
    }

    func testShiftEventsAreEmittedOnceAndLimiterIsIntermittent() {
        var mix = AudioMixModel(seed: 0x62A8)
        var engine = EngineState(); engine.isRunning = true; engine.rpm = 6300; engine.isOnLimiter = true
        var transmission = TransmissionState(); transmission.isShifting = true; transmission.shiftType = .upshift
        var shifts = 0; var cuts = 0
        for _ in 0..<120 {
            let events = mix.update(engine: engine, vehicle: VehicleState(), transmission: transmission,
                                    mode: .limiter, drivingMode: .track, tuning: AudioTuning(), deltaTime: 1.0 / 60)
            shifts += events.filter { $0.layer == .shiftTransient }.count
            cuts += events.filter { $0.layer == .limiter }.count
        }
        XCTAssertEqual(shifts, 1)
        XCTAssertTrue((5...15).contains(cuts))
        transmission.isShifting = false
        _ = mix.update(engine: engine, vehicle: VehicleState(), transmission: transmission, mode: .cruise,
                       drivingMode: .track, tuning: AudioTuning(), deltaTime: 1.0 / 60)
        transmission.isShifting = true; transmission.shiftType = .downshift
        let events = mix.update(engine: engine, vehicle: VehicleState(), transmission: transmission, mode: .revMatch,
                                drivingMode: .track, tuning: AudioTuning(), deltaTime: 1.0 / 60)
        XCTAssertEqual(events.filter { $0.layer == .revMatch }.count, 1)
    }

    @MainActor func testOfflineGraphLoopsMuteStopAndRestartWithoutBufferErrors() throws {
        let audio = EngineAudioEngine(outputMode: .offline)
        var engine = EngineState(); engine.isRunning = true
        let dt = 512.0 / 48000
        var peak: Float = 0
        for frame in 0..<400 {
            engine.rpm = 750 + Double(frame) * 14
            audio.update(engine: engine, vehicle: VehicleState(), transmission: TransmissionState(),
                         mode: .acceleration, drivingMode: .sport, deltaTime: dt)
            let rendered = try audio.render(frameCount: 512)
            for i in 0..<Int(rendered.frameLength) { peak = max(peak, abs(rendered.floatChannelData![0][i])) }
        }
        XCTAssertNil(audio.errorMessage)
        XCTAssertEqual(audio.startCount, 1, "RPM changes must never restart looping players")
        XCTAssertGreaterThan(peak, 0.001)
        XCTAssertLessThan(peak, 1)
        audio.tuning.isMuted = true
        var mutedPeak: Float = 0
        for frame in 0..<180 {
            audio.update(engine: engine, vehicle: VehicleState(), transmission: TransmissionState(),
                         mode: .idle, drivingMode: .sport, deltaTime: dt)
            let rendered = try audio.render(frameCount: 512)
            if frame > 150 {
                for i in 0..<Int(rendered.frameLength) { mutedPeak = max(mutedPeak, abs(rendered.floatChannelData![0][i])) }
            }
        }
        XCTAssertTrue(audio.isActive, "Mute keeps the graph and loop phase running")
        XCTAssertLessThan(mutedPeak, 0.00001)
        audio.tuning.isMuted = false
        engine.isRunning = false
        for _ in 0..<180 {
            audio.update(engine: engine, vehicle: VehicleState(), transmission: TransmissionState(),
                         mode: .off, drivingMode: .sport, deltaTime: dt)
        }
        XCTAssertFalse(audio.isActive)
        engine.isRunning = true
        audio.update(engine: engine, vehicle: VehicleState(), transmission: TransmissionState(),
                     mode: .idle, drivingMode: .sport, deltaTime: dt)
        XCTAssertTrue(audio.isActive)
        XCTAssertEqual(audio.startCount, 2)
        _ = try audio.render(frameCount: 512)
        audio.shutdown()
    }

    @MainActor func testFullDemoRendersBundledSamplesAndTransitionEvents() throws {
        let controller = SimulationController(automaticallyTicks: false, audioOutput: .offline)
        controller.drivingMode = .track
        controller.startDemo()
        let dt = 1024.0 / 48000
        var peak: Float = 0
        for _ in 0..<Int(45 / dt) {
            controller.advance(seconds: dt)
            let buffer = try controller.audio.render(frameCount: 1024)
            for i in 0..<Int(buffer.frameLength) {
                let sample = buffer.floatChannelData![0][i]
                XCTAssertTrue(sample.isFinite)
                peak = max(peak, abs(sample))
            }
        }
        XCTAssertTrue(controller.audio.fallbackAssets.isEmpty)
        XCTAssertEqual(controller.audio.startCount, 1)
        XCTAssertGreaterThanOrEqual(controller.audio.transientCount, 6)
        XCTAssertGreaterThan(peak, 0.001)
        XCTAssertLessThan(peak, 1)
        XCTAssertEqual(controller.operatingMode, .idle)
        controller.stopEngine()
        controller.advance(seconds: 2)
        XCTAssertFalse(controller.audio.isActive)
        controller.audio.shutdown()
    }

    func testBundledSamplesLoadAndNormalize() {
        let bank = AudioSampleBank()
        XCTAssertTrue(bank.fallbackAssets.isEmpty)
        for name in AudioSampleBank.loops.map(\.asset) + AudioSampleBank.transients {
            let buffer = bank.buffer(named: name)!
            XCTAssertEqual(buffer.format.sampleRate, 48000)
            XCTAssertEqual(buffer.format.channelCount, 1)
            XCTAssertGreaterThan(buffer.frameLength, 0)
        }
    }

    func testPreparedLoopsHaveHeadroomNoDCAndContinuousSeams() {
        let bank = AudioSampleBank()
        for sample in AudioSampleBank.loops {
            let buffer = bank.buffer(named: sample.asset)!
            let data = buffer.floatChannelData![0]
            let count = Int(buffer.frameLength)
            var sum = 0.0
            var squared = 0.0
            var peak: Float = 0
            for index in 0..<count {
                let value = Double(data[index])
                sum += value; squared += value * value; peak = max(peak, abs(data[index]))
            }
            XCTAssertLessThan(abs(sum / Double(count)), 0.001, sample.asset + " should have no loop DC offset")
            XCTAssertLessThanOrEqual(peak, 0.321)
            XCTAssertGreaterThan(sqrt(squared / Double(count)), 0.02, sample.asset + " must not be silent")
            XCTAssertLessThan(abs(data[0] - data[count - 1]), 0.08, sample.asset + " should loop without a boundary spike")
            XCTAssertGreaterThan(Double(count) / 48000, 5, "Longer loops reduce obvious repetition")
        }
    }

    @MainActor func testDevicePlaybackSessionStaysRunningAcrossRPMChanges() async throws {
        #if os(iOS)
        let audio = EngineAudioEngine(outputMode: .device)
        defer { audio.shutdown() }
        var engine = EngineState(); engine.isRunning = true; engine.load = 0.8
        var vehicle = VehicleState(); vehicle.estimatedThrottle = 0.8
        for frame in 0..<90 {
            engine.rpm = 1500 + Double(frame) * 45
            audio.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(),
                         mode: .acceleration, drivingMode: .sport, deltaTime: 1.0 / 60)
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertNil(audio.errorMessage)
        XCTAssertTrue(audio.isActive)
        XCTAssertGreaterThanOrEqual(audio.startCount, 1)
        XCTAssertLessThanOrEqual(audio.startCount, 3, "Only initial audio route configuration may require recovery")
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(audio.isActive)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        for _ in 0..<30 {
            audio.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(),
                         mode: .cruise, drivingMode: .sport, deltaTime: 1.0 / 60)
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertTrue(audio.isActive)
        XCTAssertNil(audio.errorMessage)
        audio.shutdown()
        // A pending activation must not restart twice after a rapid stop/start.
        audio.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(),
                     mode: .idle, drivingMode: .sport, deltaTime: 1.0 / 60)
        engine.isRunning = false
        audio.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(),
                     mode: .off, drivingMode: .sport, deltaTime: 1.0 / 60)
        engine.isRunning = true
        for _ in 0..<30 {
            audio.update(engine: engine, vehicle: vehicle, transmission: TransmissionState(),
                         mode: .idle, drivingMode: .sport, deltaTime: 1.0 / 60)
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertTrue(audio.isActive)
        XCTAssertNil(audio.errorMessage)
        audio.shutdown()
        XCTAssertFalse(audio.isActive)
        #else
        throw XCTSkip("AVAudioSession is tested natively on iOS")
        #endif
    }

    func testReplacementStereo44100WAVIsConvertedAndPeakLimited() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for channel in 0..<2 {
            for frame in 0..<4410 { buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.1) * 0.9 }
        }
        do {
            let file = try AVAudioFile(forWriting: directory.appendingPathComponent("idle.wav"), settings: format.settings)
            try file.write(from: buffer)
        }
        let bank = AudioSampleBank(directory: directory)
        XCTAssertFalse(bank.fallbackAssets.contains("idle"))
        let converted = bank.buffer(named: "idle")!
        XCTAssertEqual(converted.format.sampleRate, 48000)
        XCTAssertEqual(converted.format.channelCount, 1)
        XCTAssertGreaterThan(converted.frameLength, 4000)
        for i in 0..<Int(converted.frameLength) {
            XCTAssertLessThanOrEqual(abs(converted.floatChannelData![0][i]), 0.35001)
        }
    }

    func testSampleBankMissingFilesProvideFiniteSafePCM() {
        let bank = AudioSampleBank(directory: URL(fileURLWithPath: "/nonexistent/VirtualV8"))
        XCTAssertEqual(bank.fallbackAssets.count, 17)
        for name in AudioSampleBank.loops.map(\.asset) + AudioSampleBank.transients {
            let buffer = bank.buffer(named: name)!
            XCTAssertGreaterThan(buffer.frameLength, 0)
            for i in 0..<Int(buffer.frameLength) {
                let sample = buffer.floatChannelData![0][i]
                XCTAssertTrue(sample.isFinite)
                XCTAssertLessThanOrEqual(abs(sample), 0.35)
            }
        }
    }
}

import Foundation
import AVFoundation

@main struct RenderAudioPreview {
    @MainActor static func main() throws {
        guard (3...5).contains(CommandLine.arguments.count) else { throw CocoaError(.coderInvalidValue) }
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let amount = CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3]) ?? 0.5 : 0.5
        if CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "--all-classics" {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for profile in EngineProfile.classics {
                try render(profile: profile, assets: assets.appendingPathComponent(profile.audioFolder),
                           output: output.appendingPathComponent(profile.id + "-demo.wav"), amount: amount)
            }
        } else {
            let profile = CommandLine.arguments.count == 5 ? EngineProfile.available.first { $0.id == CommandLine.arguments[4] } ?? .americanV8 : .americanV8
            try render(profile: profile, assets: assets, output: output, amount: amount)
        }
    }

    @MainActor static func render(profile: EngineProfile, assets: URL, output: URL, amount: Double) throws {
        let controller = SimulationController(automaticallyTicks: false)
        controller.selectProfile(profile)
        controller.drivingMode = profile == .bmwS65 || EngineProfile.classics.contains(profile) ? .track : .sport
        let audio = EngineAudioEngine(outputMode: .offline, assetDirectory: assets, profile: profile)
        audio.tuning.backfireAmount = amount
        defer { audio.shutdown() }
        controller.startDemo()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: output, settings: settings,
                                  commonFormat: format.commonFormat, interleaved: false)
        let frames: AVAudioFrameCount = 1024
        let dt = Double(frames) / 48000
        var peak: Float = 0
        for _ in 0..<Int(44 / dt) {
            controller.advance(seconds: dt)
            audio.update(engine: controller.engine, vehicle: controller.vehicle,
                         transmission: controller.transmission, mode: controller.operatingMode,
                         drivingMode: controller.drivingMode, deltaTime: dt)
            let buffer = try audio.render(frameCount: frames)
            if let samples = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[index])) }
            }
            try file.write(from: buffer)
        }
        guard audio.errorMessage == nil, audio.fallbackAssets.isEmpty, peak > 0, peak < 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        print("Rendered 44-second \(profile.name) demo; peak \(peak), \(audio.startCount) graph starts, \(audio.transientCount) events: \(output.path)")
    }
}

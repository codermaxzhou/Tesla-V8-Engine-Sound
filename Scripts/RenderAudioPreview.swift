import Foundation
import AVFoundation

@main struct RenderAudioPreview {
    @MainActor static func main() throws {
        guard (3...4).contains(CommandLine.arguments.count) else { throw CocoaError(.coderInvalidValue) }
        let assets = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let controller = SimulationController(automaticallyTicks: false)
        controller.drivingMode = .sport
        let audio = EngineAudioEngine(outputMode: .offline, assetDirectory: assets)
        if CommandLine.arguments.count == 4 { audio.tuning.backfireAmount = Double(CommandLine.arguments[3]) ?? 0.5 }
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
        print("Rendered 44-second Sport demo; peak \(peak), \(audio.startCount) graph starts, \(audio.transientCount) events: \(output.path)")
    }
}

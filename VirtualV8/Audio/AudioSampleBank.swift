import AVFoundation

struct AudioSample {
    let asset: String
    let layer: AudioLayer
    let referenceRPM: Double
}

/// All files are replaceable. Missing/invalid WAV files fall back to original synthetic PCM.
final class AudioSampleBank {
    static let loops: [AudioSample] = [
        AudioSample(asset: "idle", layer: .idle, referenceRPM: 750),
        AudioSample(asset: "low_1500", layer: .lowRPM, referenceRPM: 1500),
        AudioSample(asset: "low_2500", layer: .lowRPM, referenceRPM: 2500),
        AudioSample(asset: "mid_3500", layer: .midRPM, referenceRPM: 3500),
        AudioSample(asset: "mid_4500", layer: .midRPM, referenceRPM: 4500),
        AudioSample(asset: "high_5500", layer: .highRPM, referenceRPM: 5500),
        AudioSample(asset: "high_6500", layer: .highRPM, referenceRPM: 6500),
        AudioSample(asset: "load", layer: .highLoad, referenceRPM: 3500),
        AudioSample(asset: "intake", layer: .intake, referenceRPM: 3500),
        AudioSample(asset: "overrun", layer: .overrun, referenceRPM: 3500)
    ]
    static func samples(for profile: EngineProfile) -> [AudioSample] {
        if let references = profile.audioReferences, references.count == 7 {
            let names = ["idle", "low_a", "low_b", "mid_a", "mid_b", "high_a", "high_b"]
            let layers: [AudioLayer] = [.idle, .lowRPM, .lowRPM, .midRPM, .midRPM, .highRPM, .highRPM]
            var samples = names.indices.map { AudioSample(asset: names[$0], layer: layers[$0], referenceRPM: references[$0]) }
            samples += [AudioSample(asset: "load", layer: .highLoad, referenceRPM: references[3]),
                        AudioSample(asset: "intake", layer: .intake, referenceRPM: references[3]),
                        AudioSample(asset: "overrun", layer: .overrun, referenceRPM: references[3])]
            if profile.hasTurbo { samples.append(AudioSample(asset: "turbo_spool", layer: .turboSpool, referenceRPM: references[3])) }
            return samples
        }
        if profile == .amgGTR {
            return loops + [AudioSample(asset: "turbo_spool", layer: .turboSpool, referenceRPM: 3500)]
        }
        if profile == .supra2JZ {
            return [
                AudioSample(asset: "idle", layer: .idle, referenceRPM: 750),
                AudioSample(asset: "low_1500", layer: .lowRPM, referenceRPM: 1500),
                AudioSample(asset: "low_2600", layer: .lowRPM, referenceRPM: 2600),
                AudioSample(asset: "mid_3600", layer: .midRPM, referenceRPM: 3600),
                AudioSample(asset: "mid_4700", layer: .midRPM, referenceRPM: 4700),
                AudioSample(asset: "high_5700", layer: .highRPM, referenceRPM: 5700),
                AudioSample(asset: "high_6600", layer: .highRPM, referenceRPM: 6600),
                AudioSample(asset: "load", layer: .highLoad, referenceRPM: 3600),
                AudioSample(asset: "intake", layer: .intake, referenceRPM: 3600),
                AudioSample(asset: "overrun", layer: .overrun, referenceRPM: 3600),
                AudioSample(asset: "turbo_spool", layer: .turboSpool, referenceRPM: 3600)
            ]
        }
        guard profile == .bmwS65 else { return loops }
        return [
            AudioSample(asset: "idle", layer: .idle, referenceRPM: 800),
            AudioSample(asset: "low_1800", layer: .lowRPM, referenceRPM: 1800),
            AudioSample(asset: "low_3200", layer: .lowRPM, referenceRPM: 3200),
            AudioSample(asset: "mid_4500", layer: .midRPM, referenceRPM: 4500),
            AudioSample(asset: "mid_5800", layer: .midRPM, referenceRPM: 5800),
            AudioSample(asset: "high_7000", layer: .highRPM, referenceRPM: 7000),
            AudioSample(asset: "high_8200", layer: .highRPM, referenceRPM: 8200),
            AudioSample(asset: "load", layer: .highLoad, referenceRPM: 4500),
            AudioSample(asset: "intake", layer: .intake, referenceRPM: 4500),
            AudioSample(asset: "overrun", layer: .overrun, referenceRPM: 4500)
        ]
    }
    let loops: [AudioSample]
    let transients: [String]
    private let firingEventsPerRevolution: Double
    static let transients = ["shift_up_1", "shift_up_2", "downshift", "pop_1", "pop_2", "pop_3", "limiter"]
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private(set) var fallbackAssets: [String] = []

    init(directory: URL? = nil, profile: EngineProfile = .americanV8) {
        loops = Self.samples(for: profile)
        firingEventsPerRevolution = profile.firingEventsPerRevolution
        transients = Self.transients + (profile.hasTurbo ? ["pressure_release_1", "pressure_release_2"] : [])
        #if SWIFT_PACKAGE
        let resources = Bundle.module.resourceURL
        #else
        let resources = Bundle.main.resourceURL
        #endif
        let root = directory ?? resources?.appendingPathComponent(profile.audioFolder)
        for name in loops.map(\.asset) + transients {
            let reference = loops.first { $0.asset == name }?.referenceRPM ?? 3500
            if let url = root?.appendingPathComponent(name + ".wav"), let buffer = try? load(url) {
                buffers[name] = buffer
            } else {
                buffers[name] = synthetic(name: name, rpm: reference)
                fallbackAssets.append(name)
            }
        }
    }

    func buffer(named name: String) -> AVAudioPCMBuffer? { buffers[name] }

    private func load(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= Int64(file.processingFormat.sampleRate * 30),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: source)
        guard let converter = AVAudioConverter(from: source.format, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format,
                frameCapacity: AVAudioFrameCount(ceil(Double(source.frameLength) * 48000 / source.format.sampleRate)) + 32) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true
            state.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, output.frameLength > 0,
              let data = output.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        var peak: Float = 0
        for i in 0..<Int(output.frameLength) {
            guard data[i].isFinite else { throw CocoaError(.fileReadCorruptFile) }
            peak = max(peak, abs(data[i]))
        }
        let scale = peak > 0.35 ? 0.35 / peak : 1
        for i in 0..<Int(output.frameLength) { data[i] *= scale }
        let isLoop = loops.contains { $0.asset == url.deletingPathExtension().lastPathComponent }
        // Envelope replacements with abrupt edges to prevent buffer-boundary clicks.
        if !isLoop || abs(data[0] - data[Int(output.frameLength) - 1]) > 0.1 {
            let edge = min(480, Int(output.frameLength) / 2)
            if edge > 0 {
                for i in 0..<edge {
                    let fade = Float(i) / Float(edge)
                    data[i] *= fade
                    data[Int(output.frameLength) - 1 - i] *= fade
                }
            }
        }
        return output
    }

    private func synthetic(name: String, rpm: Double) -> AVAudioPCMBuffer {
        let isLoop = loops.contains { $0.asset == name }
        let duration = isLoop ? 3.0 : name == "downshift" ? 0.22 : 0.10
        let count = Int(48000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let data = buffer.floatChannelData![0]
        let frequency = isLoop ? rpm / 60 * firingEventsPerRevolution : name.hasPrefix("pop") ? 85 : 160
        for i in 0..<count {
            let t = Double(i) / 48000
            let phase = 2 * Double.pi * frequency * t
            let tone = sin(phase) * 0.16 + sin(phase * 2) * 0.075 + sin(phase * 3) * 0.035
            let envelope = isLoop ? 1 : pow(sin(Double.pi * Double(i) / Double(count)), 2) * exp(-t * 12)
            data[i] = Float(tone * envelope)
        }
        return buffer
    }
}

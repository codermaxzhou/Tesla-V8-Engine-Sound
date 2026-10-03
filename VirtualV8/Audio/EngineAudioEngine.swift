import AVFoundation
import Observation

/// An immutable token owner removes its registration on whichever thread releases it.
/// No mutable audio graph state is accessed from nonisolated destruction.
private final class AudioNotificationObservation {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor @Observable
final class EngineAudioEngine {
    enum OutputMode { case device, offline, disabled }
    var tuning = AudioTuning() { didSet { onTuningChange?(tuning) } }
    @ObservationIgnored var onTuningChange: ((AudioTuning) -> Void)?
    private(set) var lastEvents: [AudioEvent] = []
    private(set) var layerGains: [AudioLayer: Double] = [:]
    private(set) var isActive = false
    private(set) var errorMessage: String?
    private(set) var fallbackAssets: [String] = []
    private(set) var startCount = 0
    private(set) var transientCount = 0

    @ObservationIgnored private let outputMode: OutputMode
    @ObservationIgnored private let assetDirectory: URL?
    private(set) var routeDescription = "Not active"
    private(set) var outputLatencyMs = 0.0
    private(set) var compensatedRPM = 0.0
    var status: String {
        if !foreground { return "Paused — app backgrounded" }
        if interrupted { return "Interrupted — resume when permitted" }
        if routePaused { return "Paused — output disconnected" }
        if let errorMessage { return "Unavailable: \(errorMessage)" }
        if isActive { return tuning.isMuted ? "Running — muted" : "Running" }
        return wantsRunning && attemptedStart ? "Starting" : "Stopped"
    }
    @ObservationIgnored private var audioEngine = AVAudioEngine()
    @ObservationIgnored private var latencyCompensator = AudioLatencyCompensator()
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var routePaused = false
    @ObservationIgnored private var bank: AudioSampleBank?
    @ObservationIgnored private var mix: AudioMixModel
    @ObservationIgnored private var voices: [Voice] = []
    @ObservationIgnored private var transients: [TransientVoice] = []
    @ObservationIgnored private var observers: [AudioNotificationObservation] = []
    @ObservationIgnored private var configurationObserver: AudioNotificationObservation?
    @ObservationIgnored private var graphReady = false
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var attemptedStart = false
    @ObservationIgnored private var lifecycleGeneration = 0
    nonisolated private static let sessionQueue = DispatchQueue(label: "VirtualV8.AudioSession", qos: .userInitiated)

    private final class Voice {
        let sample: AudioSample
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitVarispeed()
        var rate = 1.0
        init(_ sample: AudioSample) { self.sample = sample }
    }
    private final class TransientVoice {
        let player = AVAudioPlayerNode()
        var remaining = 0.0
        var layer: AudioLayer = .shiftTransient
        var gain = 0.0
        var headroom: Double { layer == .backfire ? 0.6 : 0.35 }
    }

    init(outputMode: OutputMode = .device, assetDirectory: URL? = nil, randomSeed: UInt64? = nil) {
        mix = AudioMixModel(seed: randomSeed ?? UInt64.random(in: UInt64.min...UInt64.max))
        self.outputMode = outputMode
        self.assetDirectory = assetDirectory
        guard outputMode == .device else { return }
        observeConfiguration()
        #if os(iOS)
        observers.append(AudioNotificationObservation(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.handleInterruption(began: true)
                } else {
                    self.handleInterruption(began: false,
                        shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
                }
            }
        }))
        observers.append(AudioNotificationObservation(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            Task { @MainActor [weak self] in
                self?.handleRouteChange(disconnected: reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                                        reconnected: reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue)
            }
        }))
        observers.append(AudioNotificationObservation(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.resetMediaServices() } }))
        #endif
    }

    deinit {
        audioEngine.stop()
    }

    func update(engine: EngineState, vehicle: VehicleState, transmission: TransmissionState,
                mode: EngineOperatingMode, drivingMode: DrivingMode, deltaTime: Double) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let safeRPM = latencyCompensator.rpm(for: engine, milliseconds: tuning.audioLatencyCompensationMs,
                                               deltaTime: deltaTime)
        compensatedRPM = safeRPM
        let events = mix.update(engine: engine, vehicle: vehicle, transmission: transmission,
                                mode: mode, drivingMode: drivingMode, tuning: tuning, deltaTime: deltaTime, audioRPM: safeRPM)
        lastEvents = events
        layerGains = mix.gains
        if wantsRunning != engine.isRunning {
            lifecycleGeneration += 1
            attemptedStart = false
            if engine.isRunning { interrupted = false; routePaused = false }
        }
        wantsRunning = engine.isRunning
        guard outputMode != .disabled, foreground else { return }
        if wantsRunning && !isActive && !attemptedStart && !interrupted && !routePaused { start() }
        guard isActive else {
            if !wantsRunning { attemptedStart = false }
            return
        }
        for voice in voices {
            let targetRate = min(1.15, max(0.85, safeRPM / voice.sample.referenceRPM))
            voice.rate += (targetRate - voice.rate) * (1 - exp(-8 * deltaTime))
            voice.pitch.rate = Float(voice.rate)
            voice.player.volume = Float(layerGains[voice.sample.layer, default: 0]
                * sampleWeight(voice.sample, rpm: safeRPM) * 0.35)
        }
        for voice in transients {
            voice.remaining = max(0, voice.remaining - deltaTime)
            // Preserve each event's accent while still respecting live fade/mute gains.
            voice.player.volume = tuning.isMuted ? 0 : Float(min(voice.gain,
                layerGains[voice.layer, default: 0]) * voice.headroom)
        }
        for event in events { play(event) }
        if !wantsRunning && layerGains.values.allSatisfy({ $0 < 0.0001 }) { halt() }
    }

    func setForeground(_ active: Bool) {
        guard foreground != active else { return }
        foreground = active
        lifecycleGeneration += 1
        attemptedStart = false
        latencyCompensator.reset()
        if !active { halt() }
    }

    /// Shared notification/test seams, serialized on the same actor as graph mutations.
    func handleInterruption(began: Bool, shouldResume: Bool = false) {
        lifecycleGeneration += 1
        interrupted = began || !shouldResume
        attemptedStart = false
        latencyCompensator.reset()
        if interrupted { halt() }
    }

    func handleRouteChange(disconnected: Bool, reconnected: Bool = false) {
        refreshRoute()
        if disconnected { routePaused = true }
        else if reconnected { routePaused = false }
        recover()
    }

    /// Explicit user retry also resumes after a route disconnect/non-resumable interruption.
    func retryPlayback() {
        interrupted = false; routePaused = false
        recover()
        attemptedStart = false
    }

    func resetMediaServices() {
        lifecycleGeneration += 1
        halt()
        voices.removeAll(); transients.removeAll(); bank = nil
        graphReady = false
        audioEngine = AVAudioEngine()
        if outputMode == .device { observeConfiguration() }
        attemptedStart = false
        latencyCompensator.reset()
    }

    private func observeConfiguration() {
        let observedEngine = audioEngine
        configurationObserver = AudioNotificationObservation(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Ignore initial graph setup; only a running graph needs rebuilding.
                guard let self, self.isActive, self.audioEngine === observedEngine else { return }
                self.recover()
            }
        })
    }

    private func refreshRoute() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        routeDescription = session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        if routeDescription.isEmpty { routeDescription = "No output route" }
        outputLatencyMs = session.outputLatency * 1000
        #else
        routeDescription = outputMode == .offline ? "Offline PCM rendering" : "System default output"
        #endif
    }

    /// Explicit teardown for app lifecycle/test cleanup. Normal Stop Engine fades before stopping.
    func shutdown() {
        wantsRunning = false
        attemptedStart = false
        latencyCompensator.reset()
        lifecycleGeneration += 1
        halt()
    }

    /// Offline AVAudioEngine rendering exercises the exact player graph without hardware access.
    func render(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard outputMode == .offline, isActive, frameCount > 0, frameCount <= 4096, let bank,
              let buffer = AVAudioPCMBuffer(pcmFormat: bank.format, frameCapacity: frameCount) else {
            throw CocoaError(.coderInvalidValue)
        }
        let status = try audioEngine.renderOffline(frameCount, to: buffer)
        guard status == .success else { throw CocoaError(.fileReadCorruptFile) }
        return buffer
    }

    private func prepareGraph() throws {
        guard !graphReady else { return }
        let bank = AudioSampleBank(directory: assetDirectory)
        self.bank = bank
        fallbackAssets = bank.fallbackAssets
        for sample in AudioSampleBank.loops {
            let voice = Voice(sample)
            audioEngine.attach(voice.player)
            audioEngine.attach(voice.pitch)
            audioEngine.connect(voice.player, to: voice.pitch, format: bank.format)
            audioEngine.connect(voice.pitch, to: audioEngine.mainMixerNode, format: bank.format)
            voice.player.volume = 0
            voices.append(voice)
        }
        for _ in 0..<4 {
            let voice = TransientVoice()
            audioEngine.attach(voice.player)
            audioEngine.connect(voice.player, to: audioEngine.mainMixerNode, format: bank.format)
            transients.append(voice)
        }
        if outputMode == .offline {
            try audioEngine.enableManualRenderingMode(.offline, format: bank.format, maximumFrameCount: 4096)
        }
        graphReady = true
    }

    private func start() {
        attemptedStart = true
        #if os(iOS)
        if outputMode == .device {
            let generation = lifecycleGeneration
            // Session activation may block; keep it off the simulation/UI actor.
            Self.sessionQueue.async { [weak self] in
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                    try session.setActive(true)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard generation == self.lifecycleGeneration, self.wantsRunning, self.foreground, !self.interrupted, !self.routePaused else {
                            if !self.wantsRunning { self.halt() }
                            return
                        }
                        self.startGraph()
                    }
                } catch {
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.lifecycleGeneration else { return }
                        self.halt()
                        self.errorMessage = message
                    }
                }
            }
            return
        }
        #endif
        startGraph()
    }

    private func startGraph() {
        do {
            try prepareGraph()
            audioEngine.prepare()
            try audioEngine.start()
            for voice in voices {
                guard let buffer = bank?.buffer(named: voice.sample.asset) else { continue }
                voice.player.scheduleBuffer(buffer, at: nil, options: [.loops])
                voice.player.play()
            }
            for voice in transients { voice.player.play() }
            isActive = true
            refreshRoute()
            startCount += 1
            errorMessage = nil
        } catch {
            halt()
            errorMessage = error.localizedDescription
        }
    }

    private func halt() {
        for voice in voices { voice.player.stop(); voice.player.volume = 0 }
        for voice in transients { voice.player.stop(); voice.remaining = 0 }
        audioEngine.stop()
        isActive = false
        #if os(iOS)
        if outputMode == .device {
            Self.sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }
        }
        #endif
    }

    private func recover() {
        guard isActive || wantsRunning || attemptedStart || errorMessage != nil else { return }
        lifecycleGeneration += 1
        halt()
        latencyCompensator.reset()
        attemptedStart = false
    }

    private func play(_ event: AudioEvent) {
        guard !tuning.isMuted, event.gain > 0.0001,
              let buffer = bank?.buffer(named: event.asset),
              let voice = transients.first(where: { $0.remaining == 0 }) else { return }
        voice.layer = event.layer
        voice.gain = event.gain
        voice.player.volume = Float(event.gain * voice.headroom)
        voice.player.scheduleBuffer(buffer, at: nil, options: [])
        voice.remaining = Double(buffer.frameLength) / buffer.format.sampleRate + 0.02
        transientCount += 1
    }

    private func sampleWeight(_ sample: AudioSample, rpm: Double) -> Double {
        let peers = AudioSampleBank.loops.filter { $0.layer == sample.layer }
        guard peers.count == 2 else { return 1 }
        let t = min(1, max(0, (rpm - peers[0].referenceRPM) / (peers[1].referenceRPM - peers[0].referenceRPM)))
        let blend = t * t * (3 - 2 * t)
        return sample.asset == peers[0].asset ? 1 - blend : blend
    }
}

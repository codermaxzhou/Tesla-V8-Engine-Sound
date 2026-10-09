import Foundation
import Observation

@MainActor @Observable
final class SimulationController {
    private(set) var vehicle = VehicleState()
    private(set) var engine = EngineState()
    private(set) var transmission = TransmissionState()
    private(set) var operatingMode: EngineOperatingMode = .off
    private(set) var isDemoRunning = false
    private(set) var demoElapsed: Double = 0
    private(set) var demoStage = "Ready"
    private(set) var events: [SimulationEvent] = []
    var drivingMode: DrivingMode = .comfort {
        didSet {
            guard !applyingCalibration, drivingMode != calibration.values.drivingMode else { return }
            guard canCalibrate else { applyRuntimeCalibration(); return }
            calibration.update { $0.drivingMode = drivingMode }
        }
    }
    let calibration: CalibrationSettings
    let logger = DriveLogger()
    private(set) var activeScenario: SimulationScenario?
    var inputEstimator: VehicleStateEstimator { inputMode == .simulation && activeScenario?.isLatencyTest == true ? latencyScenario?.estimator ?? sensors.estimator : sensors.estimator }
    var scenarioDuration: Double { activeScenario?.duration ?? DemoSequence.duration }
    var canCalibrate: Bool { inputMode == .simulation || (vehicle.isStopped && vehicle.speedKmh < 2.5) }
    private(set) var profile = EngineProfile.americanV8
    @ObservationIgnored private let profileDefaults: UserDefaults?
    static let profileStorageKey = "VirtualV8.engineProfile.v1"
    let phoneInput = PhoneSensorInputProvider()
    let simulationInput = SimulationInputProvider()
    var sensors: SensorInputController { phoneInput.sensors }
    @ObservationIgnored private var inputProvider: (any VehicleInputProvider)?
    private(set) var isForeground = true
    var shouldKeepScreenAwake: Bool { isForeground && inputMode == .realDrive && engine.isRunning }
    var simulationFrequencyHz: Double { 1 / Self.fixedDeltaTime }
    private(set) var inputMode: ApplicationInputMode = .simulation
    let audio: EngineAudioEngine

    @ObservationIgnored private var timerTask: Task<Void, Never>?
    static let fixedDeltaTime = 1.0 / 60.0
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var virtualEngine = VirtualEngine()
    @ObservationIgnored private var virtualTransmission = VirtualTransmission()
    @ObservationIgnored private var previousLift = false
    @ObservationIgnored private var latencyScenario: LatencyScenarioRunner?
    @ObservationIgnored private var applyingCalibration = false

    init(automaticallyTicks: Bool = true, audioOutput: EngineAudioEngine.OutputMode? = nil, settingsDefaults: UserDefaults? = nil, inputProvider: (any VehicleInputProvider)? = nil) {
        profileDefaults = settingsDefaults
        phoneInput.sensors.configurePersistence(settingsDefaults)
        let selectedProfile = EngineProfile.available.first { $0.id == settingsDefaults?.string(forKey: Self.profileStorageKey) } ?? .americanV8
        virtualEngine = VirtualEngine(configuration: selectedProfile)
        self.inputProvider = inputProvider
        calibration = CalibrationSettings(defaults: settingsDefaults)
        audio = EngineAudioEngine(outputMode: audioOutput ?? (automaticallyTicks ? .device : .disabled), profile: selectedProfile)
        profile = selectedProfile
        applyRuntimeCalibration()
        audio.onTuningChange = { [weak self] tuning in
            guard let self, !self.applyingCalibration else { return }
            self.updateCalibration { $0.audio = tuning }
        }
        sensors.onTuningChange = { [weak self] tuning in
            guard let self, !self.applyingCalibration else { return }
            self.updateCalibration { $0.estimator = tuning }
        }
        if automaticallyTicks {
            timerTask = Task { [weak self] in
                var previous = ContinuousClock.now
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(16)) }
                    catch { break }
                    let now = ContinuousClock.now
                    let elapsed = previous.duration(to: now).components
                    previous = now
                    self?.advance(seconds: min(0.2, Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18))
                }
            }
        }
    }

    deinit { timerTask?.cancel() }

    func selectInputMode(_ mode: ApplicationInputMode) {
        guard mode != inputMode else { return }
        cancelDemo()
        activeInput.stop()
        inputProvider = nil
        inputMode = mode
        activeInput.setForeground(isForeground)
        vehicle = VehicleState()
        previousLift = false
        record("Input mode: \(mode.rawValue)")
    }

    private var activeInput: any VehicleInputProvider {
        inputProvider ?? (inputMode == .simulation ? simulationInput : phoneInput)
    }

    func setForeground(_ active: Bool) {
        guard isForeground != active else { return }
        isForeground = active
        accumulator = 0
        simulationInput.setForeground(active)
        phoneInput.setForeground(active)
        inputProvider?.setForeground(active)
        audio.setForeground(active)
        if !active && logger.isLogging { logger.stop(); record("Logging stopped — app backgrounded") }
    }

    func enablePhoneInput() {
        guard inputMode == .realDrive, canCalibrate else { return }
        phoneInput.start()
    }
    func disablePhoneInput() { phoneInput.stop() }

    func updateCalibration(_ edit: (inout CalibrationValues) -> Void) {
        guard canCalibrate else { applyRuntimeCalibration(); return }
        calibration.update(edit)
        applyRuntimeCalibration()
    }
    func applyPreset(_ preset: CalibrationPreset) {
        guard canCalibrate else { return }
        calibration.apply(preset); applyRuntimeCalibration()
        record("Calibration preset: \(preset.rawValue)")
    }
    func restoreCustomCalibration() {
        guard canCalibrate else { return }
        calibration.restoreCustom(); applyRuntimeCalibration()
        record("Custom calibration restored")
    }
    private func applyRuntimeCalibration() {
        applyingCalibration = true
        drivingMode = calibration.values.drivingMode
        virtualEngine.tuning = calibration.values.engine
        virtualTransmission.tuning = calibration.values.transmission
        audio.tuning = calibration.values.audio
        sensors.tuning = calibration.values.estimator
        applyingCalibration = false
    }
    func startLogging() { guard canCalibrate else { return }; logger.start(); record("Logging started") }
    func stopLogging() { logger.stop(); record("Logging stopped") }

    /// UI selection uses catalog IDs rather than hashing the entire profile value.
    @discardableResult func selectProfile(id: String) -> Bool {
        guard canCalibrate, !engine.isRunning,
              let selected = EngineProfile.available.first(where: { $0.id == id }) else { return false }
        selectProfile(selected)
        return profile.id == id
    }

    func selectProfile(_ selected: EngineProfile) {
        guard canCalibrate, !engine.isRunning, selected != profile,
              EngineProfile.available.contains(selected) else { return }
        profile = selected
        virtualEngine = VirtualEngine(configuration: selected)
        virtualTransmission.reset()
        audio.selectProfile(selected)
        applyRuntimeCalibration()
        publishState()
        profileDefaults?.set(selected.id, forKey: Self.profileStorageKey)
        record("Engine profile: \(selected.name)")
    }

    func startEngine() {
        guard !engine.isRunning else { return }
        virtualEngine.start()
        publishState()
        record("Engine started")
    }

    func stopEngine() {
        cancelDemo()
        demoElapsed = 0
        demoStage = "Engine stopped"
        virtualEngine.stop()
        virtualTransmission.reset()
        if inputMode == .simulation { simulationInput.stop(); vehicle = simulationInput.currentState }
        previousLift = false
        accumulator = 0
        publishState()
        // Observe the off transition even when Stop/Start occur between simulation ticks.
        audio.update(engine: engine, vehicle: vehicle, transmission: transmission,
                     mode: operatingMode, drivingMode: drivingMode, deltaTime: Self.fixedDeltaTime)
        record("Engine stopped")
    }

    func setThrottle(_ value: Double) {
        selectInputMode(.simulation)
        cancelDemo()
        simulationInput.setInputs(throttle: value)
        vehicle = simulationInput.currentState
    }

    func setBrake(_ value: Double) {
        selectInputMode(.simulation)
        cancelDemo()
        simulationInput.setInputs(brake: value)
        vehicle = simulationInput.currentState
    }

    func setSpeed(_ value: Double) {
        selectInputMode(.simulation)
        cancelDemo()
        simulationInput.setInputs(speed: value)
        vehicle = simulationInput.currentState
    }

    func startDemo() {
        selectInputMode(.simulation)
        stopEngine()
        startEngine()
        activeScenario = nil
        demoElapsed = 0
        isDemoRunning = true
        demoStage = "Starting engine"
        record("Automatic demo started")
    }

    func startScenario(_ scenario: SimulationScenario) {
        selectInputMode(.simulation)
        stopEngine(); startEngine()
        latencyScenario = scenario.isLatencyTest ? LatencyScenarioRunner(tuning: sensors.tuning) : nil
        activeScenario = scenario; demoElapsed = 0; isDemoRunning = true
        demoStage = "\(scenario.rawValue) — starting engine"
        record("Scenario started: \(scenario.rawValue)")
    }

    func cancelDemo() {
        latencyScenario = nil
        guard isDemoRunning else { return }
        isDemoRunning = false
        demoStage = activeScenario == nil ? "Demo cancelled — manual control" : "Scenario cancelled — manual control"
        record("Automatic demo cancelled")
    }

    /// Accumulates elapsed time into deterministic 60 Hz steps for live use and tests.
    func advance(seconds: Double) {
        guard isForeground, seconds.isFinite, seconds > 0 else { return }
        accumulator += seconds
        while accumulator + 1e-10 >= Self.fixedDeltaTime {
            accumulator -= Self.fixedDeltaTime
            step(deltaTime: Self.fixedDeltaTime)
        }
        publishState()
    }

    private func step(deltaTime: Double) {
        // Input → transmission decision → engine response → published state.
        if isDemoRunning {
            demoElapsed = min(scenarioDuration, demoElapsed + deltaTime)
            let frame = activeScenario?.frame(at: demoElapsed) ?? DemoSequence.frame(at: demoElapsed)
            if let scenario = activeScenario, scenario.isLatencyTest, latencyScenario != nil {
                let state = latencyScenario!.update(scenario: scenario, dt: deltaTime, tuning: sensors.tuning)
                simulationInput.setSensorState(state, lift: latencyScenario!.estimator.didDetectLift)
            } else {
                simulationInput.setInputs(speed: frame.speed, throttle: frame.throttle, brake: frame.brake)
            }
            demoStage = frame.label
            if demoElapsed >= scenarioDuration - 1e-9 {
                isDemoRunning = false
                demoStage = activeScenario == nil ? "Demo complete — engine idling" : "Scenario complete — engine idling"
                record(activeScenario.map { "Scenario complete: \($0.rawValue)" } ?? "Automatic demo complete")
            }
        }
        vehicle = activeInput.update(deltaTime: deltaTime)
        let lift = activeInput.didDetectLift
        if lift && !previousLift { record("Throttle lift detected") }
        previousLift = lift
        let wasShifting = virtualTransmission.state.isShifting
        if virtualEngine.operatingMode != .starting {
            virtualTransmission.update(deltaTime: deltaTime, vehicle: vehicle,
                                       engine: virtualEngine.state, mode: drivingMode,
                                       configuration: profile)
        }
        if !wasShifting && virtualTransmission.state.isShifting {
            let shift = virtualTransmission.state
            record("\(shift.shiftType.rawValue.capitalized) \(shift.currentGear) → \(shift.targetGear)")
        }
        virtualEngine.update(deltaTime: deltaTime, vehicle: vehicle,
                             transmission: virtualTransmission, drivingMode: drivingMode)
        audio.update(engine: virtualEngine.state, vehicle: vehicle, transmission: virtualTransmission.state,
                     mode: virtualEngine.operatingMode, drivingMode: drivingMode, deltaTime: deltaTime)
        let backfire = audio.lastEvents.contains { $0.layer == .backfire }
        if backfire { record("Backfire") }
        logger.sample(deltaTime: deltaTime, timestamp: Date(), vehicle: vehicle, engine: virtualEngine.state,
                      transmission: virtualTransmission.state, mode: virtualEngine.operatingMode, backfire: backfire)
    }

    private func publishState() {
        engine = virtualEngine.state
        transmission = virtualTransmission.state
        operatingMode = virtualEngine.operatingMode
    }

    private func record(_ message: String) {
        events.insert(SimulationEvent(message: message), at: 0)
        if events.count > 200 { events.removeLast() }
    }
}

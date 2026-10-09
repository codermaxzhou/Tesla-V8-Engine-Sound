import Foundation
import Observation

struct DriveLogRecord {
    let timestamp: Date
    let speedKmh: Double
    let rawAcceleration: Double
    let filteredAcceleration: Double
    let jerk: Double
    let estimatedThrottle: Double
    let rpm: Double
    let gear: Int
    let targetGear: Int
    let engineMode: EngineOperatingMode
    let shiftType: ShiftType
    let backfireEvent: Bool
    let gpsSpeed: Double?
    let predictedSpeed: Double
    let gpsSpeedAccuracy: Double?
    let rawThrottle: Double
}

struct DriveHistoryPoint: Identifiable {
    let id: Int
    let speed: Double
    let throttle: Double
    let rpm: Double
    let gpsSpeed: Double?
    let acceleration: Double
}

/// Five samples per second, bounded session memory and a separate 60-second graph buffer.
@MainActor @Observable final class DriveLogger {
    private(set) var isLogging = false
    private(set) var records: [DriveLogRecord] = []
    private(set) var history: [DriveHistoryPoint] = []
    private(set) var latencyHistory: [DriveHistoryPoint] = []
    private(set) var exportURL: URL?
    private(set) var status = "Ready • 5 Hz • maximum one hour per session"
    static let sampleInterval = 0.2
    let maximumRecords: Int
    @ObservationIgnored private var sampleClock = 0.0
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var historySequence = 0
    @ObservationIgnored private var historyClock = 0.0
    @ObservationIgnored private var pendingBackfire = false
    @ObservationIgnored private var pendingShift = ShiftType.none

    init(maximumRecords: Int = 18_000) { self.maximumRecords = max(1, maximumRecords) }
    func start() {
        guard !isLogging else { return }
        records.removeAll(keepingCapacity: true)
        exportURL = nil
        sampleClock = 0; pendingBackfire = false; pendingShift = .none
        isLogging = true; status = "Logging at 5 Hz"
    }
    func stop() {
        guard isLogging else { return }
        isLogging = false; status = "Stopped • \(records.count) samples"
    }
    func sample(deltaTime: Double, timestamp: Date, vehicle: VehicleState, engine: EngineState,
                transmission: TransmissionState, mode: EngineOperatingMode, backfire: Bool) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        pendingBackfire = pendingBackfire || backfire
        if transmission.isShifting { pendingShift = transmission.shiftType }
        historyClock += deltaTime
        if historyClock + 1e-9 >= 0.05 {
            historyClock.formTruncatingRemainder(dividingBy: 0.05)
            historySequence += 1
            latencyHistory.append(DriveHistoryPoint(id: historySequence, speed: vehicle.speedKmh,
                throttle: vehicle.estimatedThrottle, rpm: engine.rpm,
                gpsSpeed: vehicle.gpsSpeedKmh, acceleration: vehicle.smoothedAccelerationMs2))
            if latencyHistory.count > 200 { latencyHistory.removeFirst(latencyHistory.count - 200) }
        }
        sampleClock += deltaTime
        guard sampleClock + 1e-9 >= Self.sampleInterval else { return }
        sampleClock = max(0, sampleClock - floor((sampleClock + 1e-9) / Self.sampleInterval) * Self.sampleInterval)
        sequence += 1
        history.append(DriveHistoryPoint(id: sequence, speed: vehicle.speedKmh,
                                         throttle: vehicle.estimatedThrottle, rpm: engine.rpm,
                                         gpsSpeed: vehicle.gpsSpeedKmh, acceleration: vehicle.smoothedAccelerationMs2))
        if history.count > 300 { history.removeFirst(history.count - 300) }
        if isLogging {
            records.append(DriveLogRecord(timestamp: timestamp, speedKmh: vehicle.speedKmh,
                rawAcceleration: vehicle.accelerationMs2, filteredAcceleration: vehicle.smoothedAccelerationMs2,
                jerk: vehicle.jerkMs3, estimatedThrottle: vehicle.estimatedThrottle,
                rpm: engine.rpm, gear: transmission.currentGear, targetGear: transmission.targetGear,
                engineMode: mode, shiftType: pendingShift, backfireEvent: pendingBackfire,
                gpsSpeed: vehicle.gpsSpeedKmh, predictedSpeed: vehicle.speedKmh,
                gpsSpeedAccuracy: vehicle.gpsSpeedAccuracy, rawThrottle: vehicle.rawEstimatedThrottle))
            if records.count >= maximumRecords {
                isLogging = false; status = "Session limit reached • export before starting a new log"
            }
        }
        pendingBackfire = false; pendingShift = .none
    }

    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let locale = Locale(identifier: "en_US_POSIX")
        func number(_ value: Double) -> String { String(format: "%.5f", locale: locale, value.isFinite ? value : 0) }
        let header = "timestamp,speedKmh,rawAcceleration,filteredAcceleration,jerk,estimatedThrottle,rpm,gear,targetGear,engineMode,shiftType,backfireEvent,gpsSpeed,predictedSpeed,gpsSpeedAccuracy,rawThrottle,filteredThrottle"
        let rows = records.map { row in
            [formatter.string(from: row.timestamp), number(row.speedKmh), number(row.rawAcceleration),
             number(row.filteredAcceleration), number(row.jerk), number(row.estimatedThrottle), number(row.rpm),
             String(row.gear), String(row.targetGear), row.engineMode.rawValue, row.shiftType.rawValue,
             row.backfireEvent ? "true" : "false", row.gpsSpeed.map(number) ?? "",
             number(row.predictedSpeed), row.gpsSpeedAccuracy.map(number) ?? "",
             number(row.rawThrottle), number(row.estimatedThrottle)].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
    @discardableResult func exportCSV(directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard !records.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("VirtualV8-\(UUID().uuidString).csv")
        try csv().write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
        status = "CSV ready • \(records.count) samples • use Share CSV to save to Files"
        return url
    }
}

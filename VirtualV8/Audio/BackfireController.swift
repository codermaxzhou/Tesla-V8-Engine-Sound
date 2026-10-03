import Foundation

struct BackfireController {
    struct Configuration {
        var backfireProbability: Double
        var minimumInterval: Double
        var maximumBurstCount: Int
        static func forMode(_ mode: DrivingMode) -> Configuration {
            switch mode {
            case .comfort: return Configuration(backfireProbability: 0.015, minimumInterval: 5, maximumBurstCount: 1)
            case .sport: return Configuration(backfireProbability: 0.22, minimumInterval: 2.5, maximumBurstCount: 2)
            case .track: return Configuration(backfireProbability: 0.45, minimumInterval: 1.8, maximumBurstCount: 3)
            }
        }
    }
    var configuration: Configuration

    /// At maximum tuning, every eligible downshift gets a short exhaust crackle.
    /// Below maximum, preserve the quieter Comfort / Sport / Track character.
    func downshiftBurstCount(rpm: Double, timeSinceLastBurst: Double, amount: Double, roll: Double, burstRoll: Double) -> Int {
        let amount = AudioTuning.bounded(amount)
        guard rpm.isFinite, rpm >= 1500, amount > 0, timeSinceLastBurst >= 0.55 else { return 0 }
        let probability = amount >= 0.99 ? 1 : min(0.9, configuration.backfireProbability * 3) * amount
        guard roll < probability else { return 0 }
        let maximum = min(5, max(1, Int((1 + 4 * amount).rounded())))
        let minimum = amount >= 0.75 ? 2 : 1
        let countRoll = min(0.999999, AudioTuning.bounded(burstRoll))
        return minimum + Int(countRoll * Double(maximum - minimum + 1))
    }

    func burstCount(currentThrottle: Double, previousThrottle: Double, rpm: Double,
                    engineMode: EngineOperatingMode, deceleration: Double,
                    timeSinceLastBackfire: Double, amount: Double,
                    roll: Double, burstRoll: Double) -> Int {
        guard previousThrottle > 0.6, currentThrottle < 0.15, rpm > 3000,
              (engineMode == .overrun || engineMode == .idle), deceleration <= 0.1,
              timeSinceLastBackfire >= max(0, configuration.minimumInterval),
              amount > 0, roll < AudioTuning.bounded(configuration.backfireProbability * amount) else { return 0 }
        // Single pops dominate. Longer bursts remain short and irregular.
        let maximum = min(3, max(1, configuration.maximumBurstCount))
        return burstRoll < 0.65 ? 1 : min(maximum, burstRoll < 0.93 ? 2 : 3)
    }
}

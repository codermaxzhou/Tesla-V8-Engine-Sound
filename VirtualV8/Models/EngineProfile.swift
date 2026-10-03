struct EngineProfile {
    let name: String
    let idleRPM: Double
    let redlineRPM: Double
    let softLimiterRPM: Double
    let hardLimiterRPM: Double
    var maximumRPM: Double { redlineRPM }

    static let americanV8 = EngineProfile(
        name: "American 6.2L NA V8", idleRPM: 750, redlineRPM: 6500,
        softLimiterRPM: 6400, hardLimiterRPM: 6700
    )
}

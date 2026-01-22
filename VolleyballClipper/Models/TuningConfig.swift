import Foundation

struct TuningConfig: Sendable {
    var actionEnergyThreshold: Float = 0.60
    var walkingEnergyThreshold: Float = 0.20
    var readyMaxEnergy: Float = 0.18

    var huddleScoreThreshold: Float = 10
    var resetLowEnergySeconds: Double = 2.0

    var readyStabilityWindowSeconds: Double = 1.0
    var readyActiveCountVarianceMax: Double = 1.0

    var readyTimeoutSeconds: Double = 12.0

    var enableWarmupSkipping: Bool = true
    var warmupMinSustainedActionSeconds: Double = 4.0
}


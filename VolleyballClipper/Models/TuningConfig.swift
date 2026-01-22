import Foundation

struct TuningConfig: Sendable {
    var actionEnergyThreshold: Float = 0.60
    var walkingEnergyThreshold: Float = 0.20
    var readyMaxEnergy: Float = 0.18

    var huddleScoreThreshold: Float = 10
    var resetLowEnergySeconds: Double = 2.0
    /// When energy is above `walkingEnergyThreshold` while in ACTION, decay `lowEnergySeconds` instead of resetting to zero.
    /// A value of 0.5 means it takes ~2 seconds of non-low-energy to erase 1 second accumulated.
    var lowEnergyDecayRate: Double = 0.5

    /// Enable using huddle score as an ACTION stop trigger.
    var enableHuddleStopTrigger: Bool = true
    /// Ignore huddle-based stop triggers for the first N seconds after entering ACTION.
    var minActionSecondsBeforeHuddleStop: Double = 0.3
    /// Median filter window (seconds) applied to teamEnergy for stop detection only (0 disables).
    var stopEnergyMedianWindowSeconds: Double = 0.4

    var readyStabilityWindowSeconds: Double = 1.0
    var readyActiveCountVarianceMax: Double = 1.0

    var readyTimeoutSeconds: Double = 12.0

    var enableWarmupSkipping: Bool = true
    var warmupMinSustainedActionSeconds: Double = 4.0
}

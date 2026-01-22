import Foundation

enum GameFormat: String, CaseIterable, Identifiable, Sendable {
    case beach
    case grass
    case indoor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beach: "Beach"
        case .grass: "Grass"
        case .indoor: "Indoor"
        }
    }

    var defaultTuning: TuningConfig {
        switch self {
        case .beach:
            return TuningConfig(
                actionEnergyThreshold: 0.60,
                walkingEnergyThreshold: 0.20,
                readyMaxEnergy: 0.18,
                huddleScoreThreshold: 10,
                resetLowEnergySeconds: 2.0,
                enableWarmupSkipping: true
            )
        case .grass:
            return TuningConfig(
                actionEnergyThreshold: 0.58,
                walkingEnergyThreshold: 0.20,
                readyMaxEnergy: 0.18,
                huddleScoreThreshold: 9,
                resetLowEnergySeconds: 2.0,
                enableWarmupSkipping: true
            )
        case .indoor:
            return TuningConfig(
                actionEnergyThreshold: 0.55,
                walkingEnergyThreshold: 0.20,
                readyMaxEnergy: 0.18,
                huddleScoreThreshold: 7,
                resetLowEnergySeconds: 2.0,
                enableWarmupSkipping: true
            )
        }
    }
}


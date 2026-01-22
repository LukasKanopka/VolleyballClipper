import Foundation

struct FrameMetrics: Identifiable, Sendable {
    let id: Int
    let timestamp: Double
    let activePlayerCount: Int
    let teamEnergy: Float
    let huddleScore: Float
}


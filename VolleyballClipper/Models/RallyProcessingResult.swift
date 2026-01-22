import AVFoundation
import Foundation

enum RallyState: String, Sendable {
    case idle = "IDLE"
    case ready = "READY"
    case action = "ACTION"
    case cooldown = "COOLDOWN"
}

struct RallyDebugFrame: Identifiable, Sendable {
    let id: Int
    let timestamp: Double
    let activePlayerCount: Int
    let teamEnergy: Float
    let huddleScore: Float
    let isHuddled: Bool
    let isReadyPosition: Bool
    let lowEnergySeconds: Double
    let state: RallyState
}

struct RallyProcessingResult: Sendable {
    let clips: [CMTimeRange]
    let debugFrames: [RallyDebugFrame]
}


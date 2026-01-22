import Foundation

enum BatchItemStatus: String, Sendable {
    case pending
    case analyzing
    case classifying
    case exportingDiagnostics
    case done
    case failed
    case cancelled
}

struct BatchItem: Identifiable, Sendable {
    var id = UUID()
    var url: URL
    var format: GameFormat

    var status: BatchItemStatus = .pending
    var progress: Double = 0
    var statusText: String = ""
    var predictedClipCount: Int = 0
    var diagnosticsFolder: URL?
    var error: String?

    var filename: String { url.lastPathComponent }
}

extension GameFormat {
    static func guess(from filename: String) -> GameFormat {
        let lower = filename.lowercased()
        if lower.contains("beach") { return .beach }
        if lower.contains("grass") { return .grass }
        if lower.contains("indoor") { return .indoor }
        return .indoor
    }
}


import AVFoundation
import Foundation

enum DiagnosticsExporter {
    struct Options: Sendable {
        var exportFramesCSV: Bool = true
        var exportDebugCSV: Bool = true
    }

    struct Summary: Codable, Sendable {
        struct Clip: Codable, Sendable {
            let start_s: Double
            let end_s: Double
            let duration_s: Double
        }

        let schema: Int
        let createdAt: String
        let videoFile: String
        let videoPath: String
        let format: String
        let analyzerConfig: AnalyzerConfigSnapshot
        let processingConfig: ProcessingConfigSnapshot
        let tuningConfig: TuningConfigSnapshot
        let predictedClips: [Clip]
        let frameCount: Int
        let debugFrameCount: Int
    }

    struct AnalyzerConfigSnapshot: Codable, Sendable {
        let downsampleWidth: Int
        let downsampleHeight: Int
        let minBoundingBoxHeight: Double
        let minJointConfidence: Double
        let energyMaxJointSpeed: Double
        let maxVisionRate: Double
    }

    struct ProcessingConfigSnapshot: Codable, Sendable {
        let prePadding: Double
        let postPadding: Double
        let minRallyDuration: Double
    }

    struct TuningConfigSnapshot: Codable, Sendable {
        let actionEnergyThreshold: Double
        let walkingEnergyThreshold: Double
        let readyMaxEnergy: Double
        let huddleScoreThreshold: Double
        let resetLowEnergySeconds: Double
        let readyStabilityWindowSeconds: Double
        let readyActiveCountVarianceMax: Double
        let readyTimeoutSeconds: Double
        let enableWarmupSkipping: Bool
        let warmupMinSustainedActionSeconds: Double
    }

    static func export(
        videoURL: URL,
        format: GameFormat,
        analyzerConfig: AnalyzerConfig,
        processing: ProcessingConfig,
        tuning: TuningConfig,
        frames: [FrameMetrics],
        debug: [RallyDebugFrame],
        predictedClips: [Summary.Clip],
        to outputDirectory: URL,
        options: Options
    ) throws -> URL {
        let base = videoURL.deletingPathExtension().lastPathComponent
        let runStamp = Self.timestampForFilename(Date())
        let dir = outputDirectory.appendingPathComponent("\(base)_diagnostics_\(runStamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let summary = Summary(
            schema: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            videoFile: videoURL.lastPathComponent,
            videoPath: videoURL.path,
            format: format.rawValue,
            analyzerConfig: .init(
                downsampleWidth: analyzerConfig.downsampleWidth,
                downsampleHeight: analyzerConfig.downsampleHeight,
                minBoundingBoxHeight: Double(analyzerConfig.minBoundingBoxHeight),
                minJointConfidence: Double(analyzerConfig.minJointConfidence),
                energyMaxJointSpeed: Double(analyzerConfig.energyMaxJointSpeed),
                maxVisionRate: Double(analyzerConfig.maxVisionRate)
            ),
            processingConfig: .init(
                prePadding: processing.prePadding,
                postPadding: processing.postPadding,
                minRallyDuration: processing.minRallyDuration
            ),
            tuningConfig: .init(
                actionEnergyThreshold: Double(tuning.actionEnergyThreshold),
                walkingEnergyThreshold: Double(tuning.walkingEnergyThreshold),
                readyMaxEnergy: Double(tuning.readyMaxEnergy),
                huddleScoreThreshold: Double(tuning.huddleScoreThreshold),
                resetLowEnergySeconds: tuning.resetLowEnergySeconds,
                readyStabilityWindowSeconds: tuning.readyStabilityWindowSeconds,
                readyActiveCountVarianceMax: tuning.readyActiveCountVarianceMax,
                readyTimeoutSeconds: tuning.readyTimeoutSeconds,
                enableWarmupSkipping: tuning.enableWarmupSkipping,
                warmupMinSustainedActionSeconds: tuning.warmupMinSustainedActionSeconds
            ),
            predictedClips: predictedClips,
            frameCount: frames.count,
            debugFrameCount: debug.count
        )

        try writeJSON(summary, to: dir.appendingPathComponent("summary.json"))
        try writePredictedClipsCSV(predictedClips, to: dir.appendingPathComponent("predicted_clips.csv"))

        if options.exportFramesCSV {
            try writeFramesCSV(frames, to: dir.appendingPathComponent("frames.csv"))
        }
        if options.exportDebugCSV {
            try writeDebugCSV(debug, to: dir.appendingPathComponent("debug.csv"))
        }

        return dir
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private static func writePredictedClipsCSV(_ clips: [Summary.Clip], to url: URL) throws {
        var out = "start_s,end_s,duration_s\n"
        for c in clips {
            out += "\(c.start_s),\(c.end_s),\(c.duration_s)\n"
        }
        try Data(out.utf8).write(to: url, options: [.atomic])
    }

    private static func writeFramesCSV(_ frames: [FrameMetrics], to url: URL) throws {
        var out = "id,timestamp,activePlayerCount,teamEnergy,huddleScore\n"
        out.reserveCapacity(max(1024, frames.count * 40))
        for f in frames {
            out += "\(f.id),\(f.timestamp),\(f.activePlayerCount),\(f.teamEnergy),\(f.huddleScore)\n"
        }
        try Data(out.utf8).write(to: url, options: [.atomic])
    }

    private static func writeDebugCSV(_ debug: [RallyDebugFrame], to url: URL) throws {
        var out = "id,timestamp,state,isReadyPosition,isHuddled,lowEnergySeconds,activePlayerCount,teamEnergy,huddleScore\n"
        out.reserveCapacity(max(1024, debug.count * 60))
        for d in debug {
            out += "\(d.id),\(d.timestamp),\(d.state.rawValue),\(d.isReadyPosition),\(d.isHuddled),\(d.lowEnergySeconds),\(d.activePlayerCount),\(d.teamEnergy),\(d.huddleScore)\n"
        }
        try Data(out.utf8).write(to: url, options: [.atomic])
    }

    private static func timestampForFilename(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

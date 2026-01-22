import AVFoundation
import Foundation

enum DiagnosticsExporter {
    struct Options: Sendable {
        var exportFramesCSV: Bool = true
        var exportDebugCSV: Bool = true
    }

    struct Percentiles: Codable, Sendable {
        let p10: Double
        let p50: Double
        let p90: Double
        let mean: Double
        let max: Double
        let fractionGE95: Double
    }

    struct StateStats: Codable, Sendable {
        let frameCounts: [String: Int]
        let secondsByState: [String: Double]
        let transitionCount: Int
        let cooldownTriggerCount: Int
        let cooldownReasonCounts: [String: Int]
        let actionSegmentCount: Int
        let actionSegmentDuration_s: Percentiles
        let actionSegmentGap_s: Percentiles
        let energyOverall: Percentiles
        let energyByState: [String: Percentiles]
        let huddleScoreOverall: Percentiles
        let huddleScoreByState: [String: Percentiles]
        let activeCountOverall: Percentiles
        let activeCountByState: [String: Percentiles]
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
        let videoDuration_s: Double
        let predictedCoverage_s: Double
        let predictedCoverageRatio: Double
        let frameCount: Int
        let debugFrameCount: Int
        let stateStats: StateStats
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
        let lowEnergyDecayRate: Double
        let enableHuddleStopTrigger: Bool
        let minActionSecondsBeforeHuddleStop: Double
        let stopEnergyMedianWindowSeconds: Double
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

        let duration = (frames.last?.timestamp ?? 0) - (frames.first?.timestamp ?? 0)
        let coverage = Self.coverageSeconds(predictedClips)
        let coverageRatio = duration > 0 ? (coverage / duration) : 0
        let stateStats = Self.computeStateStats(debug: debug)

        let summary = Summary(
            schema: 3,
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
                lowEnergyDecayRate: tuning.lowEnergyDecayRate,
                enableHuddleStopTrigger: tuning.enableHuddleStopTrigger,
                minActionSecondsBeforeHuddleStop: tuning.minActionSecondsBeforeHuddleStop,
                stopEnergyMedianWindowSeconds: tuning.stopEnergyMedianWindowSeconds,
                readyStabilityWindowSeconds: tuning.readyStabilityWindowSeconds,
                readyActiveCountVarianceMax: tuning.readyActiveCountVarianceMax,
                readyTimeoutSeconds: tuning.readyTimeoutSeconds,
                enableWarmupSkipping: tuning.enableWarmupSkipping,
                warmupMinSustainedActionSeconds: tuning.warmupMinSustainedActionSeconds
            ),
            predictedClips: predictedClips,
            videoDuration_s: duration,
            predictedCoverage_s: coverage,
            predictedCoverageRatio: coverageRatio,
            frameCount: frames.count,
            debugFrameCount: debug.count,
            stateStats: stateStats
        )

        try writeJSON(summary, to: dir.appendingPathComponent("summary.json"))
        try writePredictedClipsCSV(predictedClips, to: dir.appendingPathComponent("predicted_clips.csv"))
        try writeTransitionsCSV(debug, to: dir.appendingPathComponent("transitions.csv"))

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

    private static func writeTransitionsCSV(_ debug: [RallyDebugFrame], to url: URL) throws {
        guard debug.count >= 2 else {
            try Data("timestamp,from_state,to_state,activePlayerCount,teamEnergy,huddleScore,isReadyPosition,isHuddled,lowEnergySeconds\n".utf8).write(to: url, options: [.atomic])
            return
        }

        var out = "timestamp,from_state,to_state,activePlayerCount,teamEnergy,huddleScore,isReadyPosition,isHuddled,lowEnergySeconds\n"
        out.reserveCapacity(max(1024, debug.count * 40))

        var prev = debug[0]
        for row in debug.dropFirst() {
            if row.state != prev.state {
                out += "\(row.timestamp),\(prev.state.rawValue),\(row.state.rawValue),\(row.activePlayerCount),\(row.teamEnergy),\(row.huddleScore),\(row.isReadyPosition),\(row.isHuddled),\(row.lowEnergySeconds)\n"
            }
            prev = row
        }
        try Data(out.utf8).write(to: url, options: [.atomic])
    }

    private static func computeStateStats(debug: [RallyDebugFrame]) -> StateStats {
        func percentiles(_ values: [Double]) -> Percentiles {
            guard !values.isEmpty else {
                return Percentiles(p10: 0, p50: 0, p90: 0, mean: 0, max: 0, fractionGE95: 0)
            }
            let sorted = values.sorted()
            func at(_ q: Double) -> Double {
                let idx = Int((Double(sorted.count) - 1) * q)
                return sorted[max(0, min(sorted.count - 1, idx))]
            }
            let mean = sorted.reduce(0, +) / Double(sorted.count)
            let maxV = sorted.last ?? 0
            let fractionGE95 = Double(sorted.filter { $0 >= 0.95 }.count) / Double(sorted.count)
            return Percentiles(p10: at(0.10), p50: at(0.50), p90: at(0.90), mean: mean, max: maxV, fractionGE95: fractionGE95)
        }

        func dtMedian(_ rows: [RallyDebugFrame]) -> Double {
            guard rows.count >= 3 else { return 0 }
            var deltas: [Double] = []
            deltas.reserveCapacity(rows.count - 1)
            var prev = rows[0].timestamp
            for r in rows.dropFirst() {
                let dt = r.timestamp - prev
                if dt > 0, dt < 1 { deltas.append(dt) }
                prev = r.timestamp
            }
            guard !deltas.isEmpty else { return 0 }
            deltas.sort()
            return deltas[deltas.count / 2]
        }

        func actionSegments(_ rows: [RallyDebugFrame]) -> (durations: [Double], gaps: [Double]) {
            guard rows.count >= 2 else { return ([], []) }
            var segments: [(start: Double, end: Double)] = []
            var inAction = false
            var start: Double?

            for r in rows {
                if r.state == .action {
                    if !inAction {
                        inAction = true
                        start = r.timestamp
                    }
                } else if inAction {
                    inAction = false
                    if let start {
                        segments.append((start: start, end: r.timestamp))
                    }
                    start = nil
                }
            }
            if inAction, let start {
                segments.append((start: start, end: rows.last?.timestamp ?? start))
            }

            let durations = segments.map { max(0, $0.end - $0.start) }
            var gaps: [Double] = []
            if segments.count >= 2 {
                for i in 0..<(segments.count - 1) {
                    gaps.append(max(0, segments[i + 1].start - segments[i].end))
                }
            }
            return (durations, gaps)
        }

        let dt = dtMedian(debug)
        var frameCounts: [String: Int] = [:]
        var energyByState: [String: [Double]] = [:]
        var huddleByState: [String: [Double]] = [:]
        var activeByState: [String: [Double]] = [:]

        var energyAll: [Double] = []
        var huddleAll: [Double] = []
        var activeAll: [Double] = []

        energyAll.reserveCapacity(debug.count)
        huddleAll.reserveCapacity(debug.count)
        activeAll.reserveCapacity(debug.count)

        for row in debug {
            let state = row.state.rawValue
            frameCounts[state, default: 0] += 1

            energyAll.append(Double(row.teamEnergy))
            huddleAll.append(Double(row.huddleScore))
            activeAll.append(Double(row.activePlayerCount))

            energyByState[state, default: []].append(Double(row.teamEnergy))
            huddleByState[state, default: []].append(Double(row.huddleScore))
            activeByState[state, default: []].append(Double(row.activePlayerCount))
        }

        var secondsByState: [String: Double] = [:]
        for (k, v) in frameCounts {
            secondsByState[k] = Double(v) * dt
        }

        var transitionCount = 0
        if debug.count >= 2 {
            var prev = debug[0].state
            for row in debug.dropFirst() {
                if row.state != prev { transitionCount += 1 }
                prev = row.state
            }
        }

        let cooldownTriggers = debug.filter { $0.state == .cooldown }
        let cooldownReasonCounts: [String: Int] = [
            "huddle": cooldownTriggers.filter { $0.isHuddled }.count,
            "lowEnergy": cooldownTriggers.filter { !$0.isHuddled }.count,
        ]

        let seg = actionSegments(debug)
        let actionSegmentCount = seg.durations.count
        let actionSegmentDuration = percentiles(seg.durations)
        let actionSegmentGap = percentiles(seg.gaps)

        var energyByStatePct: [String: Percentiles] = [:]
        var huddleByStatePct: [String: Percentiles] = [:]
        var activeByStatePct: [String: Percentiles] = [:]
        for (k, vals) in energyByState { energyByStatePct[k] = percentiles(vals) }
        for (k, vals) in huddleByState { huddleByStatePct[k] = percentiles(vals) }
        for (k, vals) in activeByState { activeByStatePct[k] = percentiles(vals) }

        return StateStats(
            frameCounts: frameCounts,
            secondsByState: secondsByState,
            transitionCount: transitionCount,
            cooldownTriggerCount: cooldownTriggers.count,
            cooldownReasonCounts: cooldownReasonCounts,
            actionSegmentCount: actionSegmentCount,
            actionSegmentDuration_s: actionSegmentDuration,
            actionSegmentGap_s: actionSegmentGap,
            energyOverall: percentiles(energyAll),
            energyByState: energyByStatePct,
            huddleScoreOverall: percentiles(huddleAll),
            huddleScoreByState: huddleByStatePct,
            activeCountOverall: percentiles(activeAll),
            activeCountByState: activeByStatePct
        )
    }

    private static func coverageSeconds(_ clips: [Summary.Clip]) -> Double {
        guard !clips.isEmpty else { return 0 }
        let sorted = clips.sorted { $0.start_s < $1.start_s }
        var total = 0.0
        var curS = sorted[0].start_s
        var curE = sorted[0].end_s
        for c in sorted.dropFirst() {
            if c.start_s <= curE {
                curE = max(curE, c.end_s)
            } else {
                total += max(0, curE - curS)
                curS = c.start_s
                curE = c.end_s
            }
        }
        total += max(0, curE - curS)
        return total
    }

    private static func timestampForFilename(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

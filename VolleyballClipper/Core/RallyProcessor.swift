import AVFoundation
import Foundation

enum RallyProcessor {
    static func process(frames: [FrameMetrics], processing: ProcessingConfig, tuning: TuningConfig) -> RallyProcessingResult {
        guard frames.count >= 2 else {
            return RallyProcessingResult(clips: [], debugFrames: [])
        }

        var state: RallyState = .idle
        var potentialStartTime: Double?
        var actionStartTime: Double?
        var lowEnergySeconds: Double = 0
        var readySeconds: Double = 0

        var clipsRaw: [(start: Double, end: Double)] = []
        clipsRaw.reserveCapacity(64)

        var debug: [RallyDebugFrame] = []
        debug.reserveCapacity(frames.count)

        var stabilityWindow: [FrameMetrics] = []
        stabilityWindow.reserveCapacity(90)

        func isReadyPosition(_ window: [FrameMetrics]) -> Bool {
            guard let latest = window.last else { return false }
            guard latest.activePlayerCount > 0 else { return false }
            guard let earliest = window.first else { return false }
            guard (latest.timestamp - earliest.timestamp) >= (tuning.readyStabilityWindowSeconds * 0.9) else { return false }
            if latest.teamEnergy > tuning.readyMaxEnergy { return false }
            let counts = window.map(\.activePlayerCount)
            let mean = Double(counts.reduce(0, +)) / Double(counts.count)
            let variance = counts.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(counts.count)
            return variance < tuning.readyActiveCountVarianceMax
        }

        func isHuddled(_ frame: FrameMetrics) -> Bool {
            frame.huddleScore >= tuning.huddleScoreThreshold
        }

        let startTimestamp = frames.first?.timestamp ?? 0
        let endTimestamp = frames.last?.timestamp ?? startTimestamp
        var warmupGateOpened = !tuning.enableWarmupSkipping
        var firstSustainedActionStart: Double?
        var actionSustainSeconds: Double = 0

        for idx in frames.indices {
            let frame = frames[idx]
            let prev = idx > 0 ? frames[idx - 1] : frame
            let delta = max(0, frame.timestamp - prev.timestamp)

            stabilityWindow.append(frame)
            stabilityWindow.removeAll(where: { frame.timestamp - $0.timestamp > tuning.readyStabilityWindowSeconds })

            let readyPos = isReadyPosition(stabilityWindow)
            let huddled = isHuddled(frame)

            if !warmupGateOpened {
                if frame.teamEnergy >= tuning.actionEnergyThreshold {
                    if firstSustainedActionStart == nil {
                        firstSustainedActionStart = frame.timestamp
                        actionSustainSeconds = 0
                    } else {
                        actionSustainSeconds += delta
                    }
                } else {
                    firstSustainedActionStart = nil
                    actionSustainSeconds = 0
                }
                if huddled || actionSustainSeconds >= tuning.warmupMinSustainedActionSeconds {
                    warmupGateOpened = true
                }
            }

            switch state {
            case .idle:
                readySeconds = 0
                lowEnergySeconds = 0
                actionStartTime = nil
                if readyPos {
                    state = .ready
                    potentialStartTime = frame.timestamp
                    readySeconds = 0
                }

            case .ready:
                readySeconds += delta
                if frame.teamEnergy >= tuning.actionEnergyThreshold {
                    state = .action
                    actionStartTime = frame.timestamp
                } else if !readyPos {
                    state = .idle
                    potentialStartTime = nil
                } else if readySeconds >= tuning.readyTimeoutSeconds {
                    state = .idle
                    potentialStartTime = nil
                }

            case .action:
                if actionStartTime == nil { actionStartTime = frame.timestamp }

                let reset = frame.teamEnergy <= tuning.walkingEnergyThreshold
                if reset { lowEnergySeconds += delta } else { lowEnergySeconds = 0 }

                if huddled || lowEnergySeconds >= tuning.resetLowEnergySeconds {
                    let endTime = huddled ? frame.timestamp : max(startTimestamp, frame.timestamp - tuning.resetLowEnergySeconds)
                    let startTime = potentialStartTime ?? (actionStartTime ?? frame.timestamp)
                    if warmupGateOpened {
                        clipsRaw.append((start: startTime, end: endTime))
                    }
                    state = .cooldown
                }

            case .cooldown:
                // Padding is applied after we output the raw time range.
                state = .idle
                potentialStartTime = nil
                actionStartTime = nil
                lowEnergySeconds = 0
                readySeconds = 0
            }

            debug.append(
                RallyDebugFrame(
                    id: idx,
                    timestamp: frame.timestamp,
                    activePlayerCount: frame.activePlayerCount,
                    teamEnergy: frame.teamEnergy,
                    huddleScore: frame.huddleScore,
                    isHuddled: huddled,
                    isReadyPosition: readyPos,
                    lowEnergySeconds: lowEnergySeconds,
                    state: state
                )
            )
        }

        let padded = clipsRaw
            .filter { $0.end - $0.start >= processing.minRallyDuration }
            .map { raw in
                (
                    start: max(startTimestamp, raw.start - processing.prePadding),
                    end: min(endTimestamp, max(startTimestamp, raw.end + processing.postPadding))
                )
            }

        let merged = merge(clips: padded)
        let cmRanges = merged.map { CMTimeRangeFromTimeToTime(start: .init(seconds: $0.start, preferredTimescale: 600), end: .init(seconds: $0.end, preferredTimescale: 600)) }
        return RallyProcessingResult(clips: cmRanges, debugFrames: debug)
    }

    private static func merge(clips: [(start: Double, end: Double)]) -> [(start: Double, end: Double)] {
        guard !clips.isEmpty else { return [] }
        let sorted = clips.sorted { $0.start < $1.start }
        var out: [(start: Double, end: Double)] = []
        out.reserveCapacity(sorted.count)

        var cur = sorted[0]
        for next in sorted.dropFirst() {
            if next.start <= cur.end {
                cur.end = max(cur.end, next.end)
            } else {
                out.append(cur)
                cur = next
            }
        }
        out.append(cur)
        return out
    }
}

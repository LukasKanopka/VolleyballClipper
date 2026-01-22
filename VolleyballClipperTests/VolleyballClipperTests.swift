//
//  VolleyballClipperTests.swift
//  VolleyballClipperTests
//
//  Created by Lukas Kanopka on 1/21/26.
//

import AVFoundation
import Testing
@testable import VolleyballClipper

struct VolleyballClipperTests {

    @Test func detectsResetStopRallyWithPadding() async throws {
        let frames = makeFrames([
            // idle/warmup
            (0.0, 5, 0.35, 2),
            (0.5, 6, 0.30, 2),
            (1.0, 5, 0.25, 2),
            (1.5, 6, 0.30, 2),
            // ready (stable, low energy)
            (2.0, 6, 0.10, 2),
            (2.5, 6, 0.09, 2),
            (3.0, 6, 0.10, 2),
            (3.5, 6, 0.11, 2),
            // action
            (4.0, 6, 0.80, 2),
            (4.5, 6, 0.75, 2),
            (5.0, 6, 0.70, 2),
            (5.5, 6, 0.78, 2),
            (6.0, 6, 0.82, 2),
            (6.5, 6, 0.74, 2),
            (7.0, 6, 0.79, 2),
            (7.5, 6, 0.73, 2),
            // reset low energy for 2s => stop
            (8.0, 6, 0.10, 2),
            (8.5, 6, 0.10, 2),
            (9.0, 6, 0.10, 2),
            (9.5, 6, 0.10, 2),
            (10.0, 6, 0.10, 2),
            (11.0, 6, 0.10, 2),
        ])

        let processing = ProcessingConfig(prePadding: 2.0, postPadding: 3.0, minRallyDuration: 3.0)
        var tuning = TuningConfig()
        tuning.enableWarmupSkipping = false

        let result = RallyProcessor.process(frames: frames, processing: processing, tuning: tuning)
        #expect(result.clips.count == 1)
        #expect(abs(result.clips[0].start.seconds - 0.0) < 0.01)
        #expect(result.clips[0].end.seconds > 10.9)
    }

    @Test func detectsHuddleStopRally() async throws {
        let frames = makeFrames([
            (0.0, 2, 0.30, 2),
            (0.5, 2, 0.28, 2),
            (1.0, 2, 0.22, 2),
            (1.5, 2, 0.25, 2),
            (2.0, 2, 0.10, 2),
            (2.5, 2, 0.10, 2),
            (3.0, 2, 0.10, 2),
            (3.5, 2, 0.10, 2),
            (4.0, 2, 0.80, 2),
            (4.5, 2, 0.78, 2),
            (5.0, 2, 0.82, 2),
            (5.5, 2, 0.76, 2),
            (6.0, 2, 0.81, 2),
            (6.5, 2, 0.74, 2),
            (7.0, 2, 0.79, 2),
            (7.5, 2, 0.77, 2),
            // huddle spike
            (8.0, 2, 0.30, 30),
            (8.5, 2, 0.25, 30),
            (9.0, 2, 0.22, 30),
        ])

        let processing = ProcessingConfig(prePadding: 1.0, postPadding: 1.0, minRallyDuration: 1.0)
        var tuning = TuningConfig()
        tuning.huddleScoreThreshold = 10
        tuning.enableWarmupSkipping = false

        let result = RallyProcessor.process(frames: frames, processing: processing, tuning: tuning)
        #expect(result.clips.count == 1)
        #expect(abs(result.clips[0].start.seconds - 1.0) < 0.2) // 2.0 ready minus 1.0 padding
        #expect(abs(result.clips[0].end.seconds - 9.0) < 0.2) // 8.0 end plus 1.0 padding
    }

    @Test func mergesOverlappingPaddedClips() async throws {
        // Two rallies separated by 1s, but each gets 2s post/2s pre => overlaps and should merge.
        var frames: [(Double, Int, Float, Float)] = []
        var t = 0.0

        func add(_ count: Int, _ energy: Float, _ huddle: Float, seconds: Double, step: Double = 0.5) {
            var local = 0.0
            while local < seconds {
                frames.append((t, count, energy, huddle))
                t += step
                local += step
            }
        }

        add(6, 0.30, 2, seconds: 2.0) // idle
        add(6, 0.10, 2, seconds: 2.0) // ready
        add(6, 0.80, 2, seconds: 4.0) // action
        add(6, 0.10, 2, seconds: 2.5) // reset stop

        add(6, 0.30, 2, seconds: 1.0) // short gap
        add(6, 0.10, 2, seconds: 2.0) // ready
        add(6, 0.80, 2, seconds: 3.0) // action
        add(6, 0.10, 2, seconds: 2.5) // reset stop

        let metrics = makeFrames(frames)
        let processing = ProcessingConfig(prePadding: 2.0, postPadding: 2.0, minRallyDuration: 2.0)
        var tuning = TuningConfig()
        tuning.enableWarmupSkipping = false

        let result = RallyProcessor.process(frames: metrics, processing: processing, tuning: tuning)
        #expect(result.clips.count == 1)
    }

    @Test func warmupSkippingSuppressesEarlyShortActions() async throws {
        // Short action (1s) should not open warmup gate; later sustained action does.
        let frames = makeFrames([
            (0.0, 6, 0.10, 2),
            (0.5, 6, 0.10, 2),
            (1.0, 6, 0.10, 2),
            (1.5, 6, 0.10, 2),
            (2.0, 6, 0.80, 2),
            (2.5, 6, 0.80, 2),
            (3.0, 6, 0.10, 2),
            (3.5, 6, 0.10, 2),
            (4.0, 6, 0.10, 2),
            // sustained action opens gate
            (5.0, 6, 0.10, 2),
            (5.5, 6, 0.10, 2),
            (6.0, 6, 0.10, 2),
            (6.5, 6, 0.10, 2),
            (7.0, 6, 0.80, 2),
            (7.5, 6, 0.80, 2),
            (8.0, 6, 0.80, 2),
            (8.5, 6, 0.80, 2),
            (9.0, 6, 0.80, 2),
            (9.5, 6, 0.80, 2),
            (10.0, 6, 0.10, 2),
            (10.5, 6, 0.10, 2),
            (11.0, 6, 0.10, 2),
            (11.5, 6, 0.10, 2),
        ])

        let processing = ProcessingConfig(prePadding: 0.0, postPadding: 0.0, minRallyDuration: 1.0)
        var tuning = TuningConfig()
        tuning.enableWarmupSkipping = true
        tuning.warmupMinSustainedActionSeconds = 2.0

        let result = RallyProcessor.process(frames: frames, processing: processing, tuning: tuning)
        #expect(result.clips.count == 1)
        #expect(result.clips[0].start.seconds >= 0.0)
        #expect(result.clips[0].end.seconds > 9.0)
    }
}

private func makeFrames(_ tuples: [(Double, Int, Float, Float)]) -> [FrameMetrics] {
    tuples.enumerated().map { idx, t in
        FrameMetrics(id: idx, timestamp: t.0, activePlayerCount: t.1, teamEnergy: t.2, huddleScore: t.3)
    }
}

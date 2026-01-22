import AVFoundation
import Foundation

actor VideoStitcher {
    enum StitchError: Error {
        case noVideoTrack
        case cannotCreateExporter
        case exportFailed(String)
        case cancelled
    }

    func export(
        asset: AVAsset,
        ranges: [CMTimeRange],
        outputURL: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw StitchError.noVideoTrack
        }
        let audioTrack = tracks.first(where: { $0.mediaType == .audio })

        let syncSamples = try await SyncSampleIndex.build(asset: asset, track: videoTrack)
        let alignedRanges = ranges.map { syncSamples.align(range: $0, within: duration) }.filter { $0.duration.seconds > 0.01 }

        let composition = AVMutableComposition()
        guard
            let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw StitchError.cannotCreateExporter }

        let compAudio: AVMutableCompositionTrack? = audioTrack == nil ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for range in alignedRanges {
            try compVideo.insertTimeRange(range, of: videoTrack, at: cursor)
            if let audioTrack, let compAudio {
                try compAudio.insertTimeRange(range, of: audioTrack, at: cursor)
            }
            cursor = cursor + range.duration
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw StitchError.cannotCreateExporter
        }

        exporter.shouldOptimizeForNetworkUse = false
        let fileType = exporter.supportedFileTypes.contains(.mov) ? AVFileType.mov : (exporter.supportedFileTypes.first ?? .mov)

        let progressTask = Task {
            for await state in exporter.states(updateInterval: 0.2) {
                switch state {
                case .pending:
                    progress(0)
                case .waiting:
                    progress(0)
                case .exporting(let p):
                    progress(p.fractionCompleted)
                @unknown default:
                    break
                }
            }
        }
        defer { progressTask.cancel() }

        do {
            try await exporter.export(to: outputURL, as: fileType)
            progress(1.0)
        } catch is CancellationError {
            throw StitchError.cancelled
        } catch {
            throw StitchError.exportFailed(error.localizedDescription)
        }
    }
}

private struct SyncSampleIndex: Sendable {
    let times: [CMTime]

    static func build(asset: AVAsset, track: AVAssetTrack) async throws -> SyncSampleIndex {
        // Sync sample extraction is best-effort; if it fails, fall back to no alignment.
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { return SyncSampleIndex(times: []) }

            var sync: [CMTime] = []
            sync.reserveCapacity(10_000)
            while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                if isSyncSample(sample) {
                    sync.append(CMSampleBufferGetPresentationTimeStamp(sample))
                }
                if Task.isCancelled {
                    reader.cancelReading()
                    break
                }
            }
            return SyncSampleIndex(times: sync.sorted())
        } catch {
            return SyncSampleIndex(times: [])
        }
    }

    func align(range: CMTimeRange, within duration: CMTime) -> CMTimeRange {
        guard !times.isEmpty else { return range }
        let start = max(.zero, min(duration, range.start))
        let end = max(start, min(duration, range.end))

        let alignedStart = nearestSync(atOrBefore: start) ?? start
        let alignedEnd = nearestSync(atOrAfter: end) ?? end
        return CMTimeRangeFromTimeToTime(start: alignedStart, end: max(alignedStart, alignedEnd))
    }

    private func nearestSync(atOrBefore t: CMTime) -> CMTime? {
        var lo = 0
        var hi = times.count - 1
        var best: CMTime?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if times[mid] <= t {
                best = times[mid]
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    private func nearestSync(atOrAfter t: CMTime) -> CMTime? {
        var lo = 0
        var hi = times.count - 1
        var best: CMTime?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if times[mid] >= t {
                best = times[mid]
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        return best
    }

    private static func isSyncSample(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) else {
            return false
        }
        let array = attachments as NSArray
        guard let dict = array.firstObject as? NSDictionary else { return false }
        if let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        return true
    }
}

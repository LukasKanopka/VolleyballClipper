import AVFoundation
import CoreGraphics
import Foundation
import Vision

actor VideoAnalyzer {
    struct AnalysisResult: Sendable {
        let frames: [FrameMetrics]
    }

    enum AnalyzerError: Error {
        case noVideoTrack
        case readerFailed
        case cancelled
    }

    func analyze(
        asset: AVAsset,
        config: AnalyzerConfig,
        progress: @Sendable @escaping (_ pct: Double, _ timestamp: Double) -> Void
    ) async throws -> AnalysisResult {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw AnalyzerError.noVideoTrack
        }

        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        let stride = max(1, Int((nominalFPS / config.maxVisionRate).rounded(.up)))

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: config.downsampleWidth,
            kCVPixelBufferHeightKey as String: config.downsampleHeight,
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let request = VNDetectHumanBodyPoseRequest()

        var frames: [FrameMetrics] = []
        frames.reserveCapacity(Int(duration.seconds * Double(min(nominalFPS, config.maxVisionRate))) + 1000)

        var prevPlayerJoints: [[VNHumanBodyPoseObservation.JointName: CGPoint]] = []
        var prevTime: Double?

        guard reader.startReading() else { throw AnalyzerError.readerFailed }

        var frameIndex = 0
        while reader.status == .reading {
            if Task.isCancelled {
                reader.cancelReading()
                throw AnalyzerError.cancelled
            }

            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            defer { frameIndex += 1 }
            if frameIndex % stride != 0 { continue }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []

            let players = try observations.compactMap { observation -> (centroid: CGPoint, joints: [VNHumanBodyPoseObservation.JointName: CGPoint])? in
                let points = try observation.recognizedPoints(.all)
                guard let bbox = Self.normalizedBoundingBox(points: points, minConfidence: config.minJointConfidence) else {
                    return nil
                }
                guard bbox.height >= config.minBoundingBoxHeight else { return nil }

                let centroid = CGPoint(x: bbox.midX, y: bbox.midY)
                var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
                for joint in [
                    VNHumanBodyPoseObservation.JointName.leftWrist,
                    .rightWrist,
                    .leftAnkle,
                    .rightAnkle,
                ] {
                    if let p = points[joint], p.confidence >= config.minJointConfidence {
                        joints[joint] = p.location
                    }
                }
                return (centroid, joints)
            }
            .sorted(by: { $0.centroid.x < $1.centroid.x })

            let centroids = players.map { $0.centroid }
            let playerJoints = players.map { $0.joints }

            let huddleScore = Self.computeHuddleScore(centroids: centroids)
            let teamEnergy = Self.computeTeamEnergy(
                current: playerJoints,
                previous: prevPlayerJoints,
                currentTime: time,
                previousTime: prevTime,
                energyMaxJointSpeed: config.energyMaxJointSpeed
            )

            frames.append(
                FrameMetrics(
                    id: frames.count,
                    timestamp: time,
                    activePlayerCount: players.count,
                    teamEnergy: teamEnergy,
                    huddleScore: huddleScore
                )
            )

            prevPlayerJoints = playerJoints
            prevTime = time

            if duration.seconds > 0 {
                progress(min(1, time / duration.seconds), time)
            }
        }

        if reader.status == .failed { throw AnalyzerError.readerFailed }
        return AnalysisResult(frames: frames)
    }

    private static func computeTeamEnergy(
        current: [[VNHumanBodyPoseObservation.JointName: CGPoint]],
        previous: [[VNHumanBodyPoseObservation.JointName: CGPoint]],
        currentTime: Double,
        previousTime: Double?,
        energyMaxJointSpeed: Float
    ) -> Float {
        guard let previousTime, currentTime > previousTime else { return 0 }
        let dt = Float(currentTime - previousTime)
        let n = min(current.count, previous.count)
        if n == 0 { return 0 }

        var totalSpeed: Float = 0
        var comparisons: Float = 0

        for i in 0..<n {
            let cur = current[i]
            let prev = previous[i]
            for joint in [
                VNHumanBodyPoseObservation.JointName.leftWrist,
                .rightWrist,
                .leftAnkle,
                .rightAnkle,
            ] {
                guard let p0 = prev[joint], let p1 = cur[joint] else { continue }
                let dx = Float(p1.x - p0.x)
                let dy = Float(p1.y - p0.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                totalSpeed += dist / max(0.0001, dt)
                comparisons += 1
            }
        }

        if comparisons == 0 { return 0 }
        let avgSpeed = totalSpeed / comparisons
        return max(0, min(1, avgSpeed / max(0.0001, energyMaxJointSpeed)))
    }

    private static func computeHuddleScore(centroids: [CGPoint]) -> Float {
        guard centroids.count >= 2 else { return 0 }
        let meanX = centroids.map(\.x).reduce(0, +) / Double(centroids.count)
        let meanY = centroids.map(\.y).reduce(0, +) / Double(centroids.count)

        let meanSq = centroids.reduce(0.0) { acc, p in
            let dx = p.x - meanX
            let dy = p.y - meanY
            return acc + (dx * dx + dy * dy)
        } / Double(centroids.count)

        let stdDev = sqrt(meanSq)
        return Float(1.0 / max(0.001, stdDev))
    }

    private static func normalizedBoundingBox(
        points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        minConfidence: Float
    ) -> CGRect? {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var any = false

        for (_, p) in points {
            guard p.confidence >= minConfidence else { continue }
            any = true
            minX = min(minX, p.location.x)
            minY = min(minY, p.location.y)
            maxX = max(maxX, p.location.x)
            maxY = max(maxY, p.location.y)
        }

        guard any else { return nil }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}

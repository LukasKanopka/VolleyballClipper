import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var inputDurationSeconds: Double?

    @Published var gameFormat: GameFormat = .beach
    @Published var processingConfig = ProcessingConfig()
    @Published var tuningConfig = TuningConfig()
    @Published var analyzerConfig = AnalyzerConfig()

    @Published var keepDebugTimeline = true

    @Published var isAnalyzing = false
    @Published var isExporting = false
    @Published var progress: Double = 0
    @Published var statusText: String = ""
    @Published var lastError: String?

    @Published private(set) var frames: [FrameMetrics] = []
    @Published private(set) var debugTimeline: [RallyDebugFrame] = []
    @Published private(set) var clips: [CMTimeRange] = []

    @Published var batchItems: [BatchItem] = []
    @Published var batchOutputDirectory: URL?
    @Published var batchIsRunning = false
    @Published var batchOverallProgress: Double = 0
    @Published var batchStatusText: String = ""
    @Published var batchUsePerFormatDefaults = true
    @Published var batchExportFramesCSV = true
    @Published var batchExportDebugCSV = true
    @Published var batchWarmupSkippingEnabled = true
    @Published var batchWarmupMinSustainedActionSeconds: Double = 4.0

    private let analyzer = VideoAnalyzer()
    private let stitcher = VideoStitcher()

    private var inputAccess: SecurityScopedAccess?
    private var analysisTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?

    var totalClipDurationSeconds: Double {
        clips.reduce(0) { $0 + $1.duration.seconds }
    }

    func applyDefaults(for format: GameFormat) {
        processingConfig = ProcessingConfig()
        tuningConfig = format.defaultTuning
        analyzerConfig = AnalyzerConfig()
    }

    func setInputURL(_ url: URL) {
        inputAccess?.stop()
        inputAccess = SecurityScopedAccess(url: url)
        _ = inputAccess?.start()

        inputURL = url
        inputDurationSeconds = nil
        frames = []
        clips = []
        debugTimeline = []
        lastError = nil

        Task {
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                await MainActor.run { self.inputDurationSeconds = duration.seconds }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func startAnalysis() {
        guard let inputURL else { return }
        lastError = nil
        analysisTask?.cancel()
        exportTask?.cancel()
        isAnalyzing = true
        progress = 0
        statusText = "Analyzing video…"

        analysisTask = Task {
            do {
                let asset = AVURLAsset(url: inputURL)

                let result = try await analyzer.analyze(
                    asset: asset,
                    config: analyzerConfig,
                    progress: { [weak self] pct, t in
                        Task { @MainActor in
                            self?.progress = pct
                            self?.statusText = "Analyzing… \(t.formatted(.number.precision(.fractionLength(1))))s"
                        }
                    }
                )

                await MainActor.run {
                    self.frames = result.frames
                    self.progress = 1
                    self.statusText = "Classifying…"
                }

                reclassifyFromExistingFrames()
            } catch is CancellationError {
                await MainActor.run {
                    self.lastError = nil
                    self.isAnalyzing = false
                    self.progress = 0
                    self.statusText = "Cancelled"
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isAnalyzing = false
                    self.statusText = ""
                }
            }
        }
    }

    func reclassifyFromExistingFrames() {
        guard !frames.isEmpty else { return }
        let result = RallyProcessor.process(frames: frames, processing: processingConfig, tuning: tuningConfig)

        clips = result.clips
        debugTimeline = keepDebugTimeline ? result.debugFrames : []
        isAnalyzing = false
        progress = 0
        statusText = "Ready"
    }

    func startExport() {
        exportTask?.cancel()
        exportTask = Task { await chooseExportAndStart() }
    }

    func cancelWork() {
        analysisTask?.cancel()
        exportTask?.cancel()
    }

    func setBatchURLs(_ urls: [URL]) {
        batchItems = urls.map { url in
            BatchItem(url: url, format: GameFormat.guess(from: url.lastPathComponent))
        }
        batchOverallProgress = 0
        batchStatusText = ""
    }

    func chooseBatchOutputDirectory() {
        batchTask?.cancel()
        Task {
            let url = await OpenPanel.pickOutputDirectory()
            await MainActor.run { self.batchOutputDirectory = url }
        }
    }

    func startBatch() {
        guard !batchIsRunning else { return }
        guard batchOutputDirectory != nil else {
            lastError = "Pick an output directory first."
            return
        }
        guard !batchItems.isEmpty else {
            lastError = "Pick one or more videos first."
            return
        }

        lastError = nil
        batchIsRunning = true
        batchOverallProgress = 0
        batchStatusText = "Starting…"

        batchTask?.cancel()
        batchTask = Task { await runBatch() }
    }

    func cancelBatch() {
        batchTask?.cancel()
    }

    private func runBatch() async {
        guard let outputDir = batchOutputDirectory else { return }
        let outputAccess = SecurityScopedAccess(url: outputDir)
        _ = outputAccess.start()
        defer { outputAccess.stop() }

        let total = max(1, batchItems.count)
        var completed = 0

        for idx in batchItems.indices {
            if Task.isCancelled {
                await MainActor.run {
                    self.batchIsRunning = false
                    self.batchStatusText = "Cancelled"
                }
                return
            }

            await MainActor.run {
                self.batchItems[idx].status = .analyzing
                self.batchItems[idx].progress = 0
                self.batchItems[idx].error = nil
                self.batchItems[idx].diagnosticsFolder = nil
                self.batchItems[idx].statusText = "Analyzing…"
                self.batchStatusText = "\(idx + 1)/\(total): \(self.batchItems[idx].filename)"
                self.batchOverallProgress = (Double(completed) / Double(total))
            }

            let url = batchItems[idx].url
            let format = batchItems[idx].format
            let inputAccess = SecurityScopedAccess(url: url)
            _ = inputAccess.start()
            defer { inputAccess.stop() }

            do {
                let asset = AVURLAsset(url: url)
                let frames = try await analyzer.analyze(
                    asset: asset,
                    config: analyzerConfig,
                    progress: { [weak self] pct, t in
                        Task { @MainActor in
                            guard let self else { return }
                            self.batchItems[idx].progress = pct
                            self.batchItems[idx].statusText = "Analyzing… \(t.formatted(.number.precision(.fractionLength(1))))s"
                            self.batchOverallProgress = (Double(completed) + pct) / Double(total)
                        }
                    }
                ).frames

                if Task.isCancelled { throw CancellationError() }

                await MainActor.run {
                    self.batchItems[idx].status = .classifying
                    self.batchItems[idx].statusText = "Classifying…"
                    self.batchItems[idx].progress = 1
                    self.batchOverallProgress = (Double(completed) + 1) / Double(total)
                }

                let processing = processingConfig
                var tuning = batchUsePerFormatDefaults ? format.defaultTuning : tuningConfig
                tuning.enableWarmupSkipping = batchWarmupSkippingEnabled
                tuning.warmupMinSustainedActionSeconds = batchWarmupMinSustainedActionSeconds
                let result = RallyProcessor.process(frames: frames, processing: processing, tuning: tuning)
                let clipSummaries = result.clips.map { r in
                    DiagnosticsExporter.Summary.Clip(start_s: r.start.seconds, end_s: r.end.seconds, duration_s: r.duration.seconds)
                }
                let analyzerCfg = analyzerConfig
                let exportFrames = batchExportFramesCSV
                let exportDebug = batchExportDebugCSV
                let debugFrames = result.debugFrames

                await MainActor.run {
                    self.batchItems[idx].status = .exportingDiagnostics
                    self.batchItems[idx].statusText = "Exporting diagnostics…"
                    self.batchItems[idx].predictedClipCount = result.clips.count
                }

                let diagDir = try await Task.detached {
                    try DiagnosticsExporter.export(
                        videoURL: url,
                        format: format,
                        analyzerConfig: analyzerCfg,
                        processing: processing,
                        tuning: tuning,
                        frames: frames,
                        debug: debugFrames,
                        predictedClips: clipSummaries,
                        to: outputDir,
                        options: .init(exportFramesCSV: exportFrames, exportDebugCSV: exportDebug)
                    )
                }.value

                await MainActor.run {
                    self.batchItems[idx].status = .done
                    self.batchItems[idx].diagnosticsFolder = diagDir
                    self.batchItems[idx].statusText = "Done"
                    self.batchItems[idx].progress = 1
                }
                completed += 1
                await MainActor.run {
                    self.batchOverallProgress = Double(completed) / Double(total)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.batchItems[idx].status = .cancelled
                    self.batchItems[idx].statusText = "Cancelled"
                    self.batchItems[idx].progress = 0
                    self.batchIsRunning = false
                    self.batchStatusText = "Cancelled"
                }
                return
            } catch {
                await MainActor.run {
                    self.batchItems[idx].status = .failed
                    self.batchItems[idx].error = error.localizedDescription
                    self.batchItems[idx].statusText = "Failed"
                    self.batchItems[idx].progress = 0
                }
                completed += 1
                await MainActor.run {
                    self.batchOverallProgress = Double(completed) / Double(total)
                }
            }
        }

        await MainActor.run {
            self.batchIsRunning = false
            self.batchStatusText = "Batch complete"
        }
    }

    private func chooseExportAndStart() async {
        guard let inputURL, !clips.isEmpty else { return }
        lastError = nil

        guard let destinationURL = await SavePanel.pickMovieDestination(defaultName: inputURL.deletingPathExtension().lastPathComponent + "-highlights") else {
            return
        }

        let outputAccess = SecurityScopedAccess(url: destinationURL)
        _ = outputAccess.start()
        defer { outputAccess.stop() }

        isExporting = true
        progress = 0
        statusText = "Exporting…"

        do {
            let asset = AVURLAsset(url: inputURL)
            try await stitcher.export(
                asset: asset,
                ranges: clips,
                outputURL: destinationURL,
                progress: { [weak self] p in
                    Task { @MainActor in
                        self?.progress = p
                    }
                }
            )
            isExporting = false
            statusText = "Export complete"
        } catch is CancellationError {
            lastError = nil
            isExporting = false
            progress = 0
            statusText = "Cancelled"
        } catch {
            lastError = error.localizedDescription
            isExporting = false
            statusText = ""
        }
    }
}

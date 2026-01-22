import SwiftUI
import UniformTypeIdentifiers

struct ProcessView: View {
    @ObservedObject var model: AppModel

    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Input") {
                    HStack {
                        Button("Choose Video…") { isImporting = true }
                        if let url = model.inputURL {
                            Text(url.lastPathComponent)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No video selected")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let duration = model.inputDurationSeconds {
                        Text("Duration: \(duration.formatted(.number.precision(.fractionLength(1))))s")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Format") {
                    Picker("Game Type", selection: $model.gameFormat) {
                        ForEach(GameFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Cut Settings") {
                    LabeledContent("Pre-padding") {
                        Stepper(
                            value: $model.processingConfig.prePadding,
                            in: 0...10,
                            step: 0.5
                        ) { Text("\(model.processingConfig.prePadding, specifier: "%.1f")s") }
                    }
                    LabeledContent("Post-padding") {
                        Stepper(
                            value: $model.processingConfig.postPadding,
                            in: 0...10,
                            step: 0.5
                        ) { Text("\(model.processingConfig.postPadding, specifier: "%.1f")s") }
                    }
                    LabeledContent("Min rally duration") {
                        Stepper(
                            value: $model.processingConfig.minRallyDuration,
                            in: 0...20,
                            step: 0.5
                        ) { Text("\(model.processingConfig.minRallyDuration, specifier: "%.1f")s") }
                    }
                }

                Section("Analysis") {
                    Toggle("Keep debug timeline", isOn: $model.keepDebugTimeline)

                    LabeledContent("Downsample size") {
                        Text("\(model.analyzerConfig.downsampleWidth)x\(model.analyzerConfig.downsampleHeight)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Bounding box min height") {
                        Text("\(model.analyzerConfig.minBoundingBoxHeight, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Warmup skipping", isOn: $model.tuningConfig.enableWarmupSkipping)
                    LabeledContent("Warmup min sustained action") {
                        Stepper(value: $model.tuningConfig.warmupMinSustainedActionSeconds, in: 0...20, step: 0.5) {
                            Text("\(model.tuningConfig.warmupMinSustainedActionSeconds, specifier: "%.1f")s")
                        }
                    }
                }

                Section("Actions") {
                    HStack {
                        Button(model.isAnalyzing ? "Analyzing…" : "Analyze & Classify") {
                            model.startAnalysis()
                        }
                        .disabled(model.inputURL == nil || model.isAnalyzing || model.isExporting)

                        Spacer()

                        Button(model.isExporting ? "Exporting…" : "Export Highlights…") {
                            model.startExport()
                        }
                        .disabled(model.clips.isEmpty || model.isAnalyzing || model.isExporting)
                    }

                    if model.isAnalyzing || model.isExporting {
                        HStack {
                            Spacer()
                            Button("Cancel") { model.cancelWork() }
                        }
                        ProgressView(value: model.progress)
                        Text(model.statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if !model.clips.isEmpty {
                        LabeledContent("Clips") { Text("\(model.clips.count)") }
                        LabeledContent("Total output") {
                            Text(model.totalClipDurationSeconds.formatted(.number.precision(.fractionLength(1))) + "s")
                        }
                    }

                    if let error = model.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if !model.clips.isEmpty {
                    Section("Preview") {
                        ClipListView(clips: model.clips)
                    }
                }
            }
            .navigationTitle("Volleyball Auto-Editor")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.setInputURL(url)
            case .failure(let error):
                model.lastError = error.localizedDescription
            }
        }
        .onChange(of: model.gameFormat) { _, newValue in
            model.applyDefaults(for: newValue)
        }
    }
}

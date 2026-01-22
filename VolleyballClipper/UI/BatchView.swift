import SwiftUI
import UniformTypeIdentifiers

struct BatchView: View {
    @ObservedObject var model: AppModel

    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Inputs") {
                    Button("Choose Videos…") { isImporting = true }
                        .disabled(model.batchIsRunning)

                    if !model.batchItems.isEmpty {
                        Text("\(model.batchItems.count) video(s) selected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Output") {
                    HStack {
                        Button("Choose Output Folder…") { model.chooseBatchOutputDirectory() }
                            .disabled(model.batchIsRunning)
                        if let dir = model.batchOutputDirectory {
                            Text(dir.path)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No folder selected")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Export frames.csv", isOn: $model.batchExportFramesCSV)
                        .disabled(model.batchIsRunning)
                    Toggle("Export debug.csv", isOn: $model.batchExportDebugCSV)
                        .disabled(model.batchIsRunning)

                    Toggle("Use per-format defaults", isOn: $model.batchUsePerFormatDefaults)
                        .disabled(model.batchIsRunning)

                    Toggle("Warmup skipping", isOn: $model.batchWarmupSkippingEnabled)
                        .disabled(model.batchIsRunning)
                    if model.batchWarmupSkippingEnabled {
                        LabeledContent("Warmup min sustained action") {
                            Stepper(value: $model.batchWarmupMinSustainedActionSeconds, in: 0...20, step: 0.5) {
                                Text("\(model.batchWarmupMinSustainedActionSeconds, specifier: "%.1f")s")
                            }
                        }
                        .disabled(model.batchIsRunning)
                    }
                }

                Section("Run") {
                    HStack {
                        Button(model.batchIsRunning ? "Running…" : "Run Batch") { model.startBatch() }
                            .disabled(model.batchIsRunning || model.batchItems.isEmpty || model.batchOutputDirectory == nil)
                        Spacer()
                        Button("Cancel") { model.cancelBatch() }
                            .disabled(!model.batchIsRunning)
                    }

                    if model.batchIsRunning || model.batchOverallProgress > 0 {
                        ProgressView(value: model.batchOverallProgress)
                        Text(model.batchStatusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.batchItems.isEmpty {
                    Section("Queue") {
                        ForEach($model.batchItems) { $item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.filename)
                                        .lineLimit(1)
                                    Spacer()
                                    Picker("", selection: $item.format) {
                                        ForEach(GameFormat.allCases) { f in
                                            Text(f.displayName).tag(f)
                                        }
                                    }
                                    .labelsHidden()
                                    .disabled(model.batchIsRunning)
                                    .frame(width: 140)
                                }

                                HStack {
                                    Text(item.status.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if item.progress > 0, item.status == .analyzing {
                                        Spacer()
                                        ProgressView(value: item.progress)
                                            .frame(width: 140)
                                    }
                                }

                                if !item.statusText.isEmpty {
                                    Text(item.statusText)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }

                                if item.predictedClipCount > 0 {
                                    Text("Predicted clips: \(item.predictedClipCount)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }

                                if let folder = item.diagnosticsFolder {
                                    Text("Diagnostics: \(folder.path)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                if let error = item.error {
                                    Text(error)
                                        .font(.callout)
                                        .foregroundStyle(.red)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Batch Runner")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.setBatchURLs(urls)
            case .failure(let error):
                model.lastError = error.localizedDescription
            }
        }
    }
}

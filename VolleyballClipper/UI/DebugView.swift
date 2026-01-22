import Charts
import SwiftUI

struct DebugView: View {
    @ObservedObject var model: AppModel

    @State private var selection: Double?

    var body: some View {
        NavigationStack {
            if model.frames.isEmpty {
                ContentUnavailableView("No analysis yet", systemImage: "waveform.path.ecg", description: Text("Run Analyze & Classify to see tuning and state timelines."))
                    .navigationTitle("Debug & Tuning")
            } else {
                Form {
                    Section("Tuning") {
                        LabeledContent("Action energy threshold") {
                            Slider(
                                value: Binding(
                                    get: { Double(model.tuningConfig.actionEnergyThreshold) },
                                    set: { model.tuningConfig.actionEnergyThreshold = Float($0) }
                                ),
                                in: 0...1,
                                step: 0.01
                            )
                        }
                        LabeledContent("Walking energy threshold") {
                            Slider(
                                value: Binding(
                                    get: { Double(model.tuningConfig.walkingEnergyThreshold) },
                                    set: { model.tuningConfig.walkingEnergyThreshold = Float($0) }
                                ),
                                in: 0...1,
                                step: 0.01
                            )
                        }
                        LabeledContent("Ready (max) energy") {
                            Slider(
                                value: Binding(
                                    get: { Double(model.tuningConfig.readyMaxEnergy) },
                                    set: { model.tuningConfig.readyMaxEnergy = Float($0) }
                                ),
                                in: 0...1,
                                step: 0.01
                            )
                        }
                        LabeledContent("Huddle score threshold") {
                            Slider(
                                value: Binding(
                                    get: { Double(model.tuningConfig.huddleScoreThreshold) },
                                    set: { model.tuningConfig.huddleScoreThreshold = Float($0) }
                                ),
                                in: 0...50,
                                step: 0.5
                            )
                        }
                        LabeledContent("Reset low-energy seconds") {
                            Stepper(value: $model.tuningConfig.resetLowEnergySeconds, in: 0.5...6.0, step: 0.5) {
                                Text("\(model.tuningConfig.resetLowEnergySeconds, specifier: "%.1f")s")
                            }
                        }

                        HStack {
                            Button("Re-run classification") { model.reclassifyFromExistingFrames() }
                                .disabled(model.isAnalyzing || model.isExporting)
                            Spacer()
                            Toggle("Warmup skip", isOn: $model.tuningConfig.enableWarmupSkipping)
                        }
                    }

                    Section("Timeline") {
                        Chart {
                            ForEach(model.debugTimeline) { row in
                                LineMark(
                                    x: .value("t", row.timestamp),
                                    y: .value("Team Energy", Double(row.teamEnergy))
                                )
                                .foregroundStyle(by: .value("State", row.state.rawValue))
                            }

                            ForEach(model.debugTimeline.filter { $0.isHuddled }) { row in
                                PointMark(x: .value("t", row.timestamp), y: .value("Huddle", Double(row.teamEnergy)))
                                    .symbolSize(30)
                                    .foregroundStyle(.green)
                            }

                            RuleMark(y: .value("Action Threshold", Double(model.tuningConfig.actionEnergyThreshold)))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        .chartXSelection(value: $selection)
                        .frame(minHeight: 240)

                        Chart {
                            ForEach(model.debugTimeline) { row in
                                LineMark(
                                    x: .value("t", row.timestamp),
                                    y: .value("Huddle Score", Double(row.huddleScore))
                                )
                                .foregroundStyle(.blue)
                            }
                            RuleMark(y: .value("Huddle Threshold", Double(model.tuningConfig.huddleScoreThreshold)))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        .chartXSelection(value: $selection)
                        .frame(minHeight: 160)

                        if let selection, let row = model.debugTimeline.closest(to: selection) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("t=\(row.timestamp, specifier: "%.2f")s • state=\(row.state.rawValue)")
                                    .font(.callout)
                                Text("active=\(row.activePlayerCount) • energy=\(row.teamEnergy, specifier: "%.3f") • huddleScore=\(row.huddleScore, specifier: "%.2f") • lowEnergy=\(row.lowEnergySeconds, specifier: "%.1f")s")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !model.clips.isEmpty {
                        Section("Clips") { ClipListView(clips: model.clips) }
                    }
                }
                .navigationTitle("Debug & Tuning")
            }
        }
    }
}

private extension Array where Element == RallyDebugFrame {
    func closest(to timestamp: Double) -> RallyDebugFrame? {
        guard !isEmpty else { return nil }
        var best = self[0]
        var bestDist = abs(best.timestamp - timestamp)
        for row in self.dropFirst() {
            let d = abs(row.timestamp - timestamp)
            if d < bestDist {
                best = row
                bestDist = d
            }
        }
        return best
    }
}

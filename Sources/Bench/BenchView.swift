// BenchView — the Bench tab: pick a cataloged chat model, Run, get a result card and a
// shareable JSON blob. The blob (not a screenshot, not a typed number) is the submission unit:
// paste it into the zoo's bench-result issue form and your device row appears in BENCHMARKS.md
// after aggregation. See BenchRunner for the protocol (zoo-chat-v1) and how it's measured.

import CoreAIKitUI
import SwiftUI

struct BenchView: View {
    @State private var runner = BenchRunner()
    @State private var entries: [CatalogEntry] = []
    @State private var selected: CatalogEntry?
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modelPanel
                    if let blob = runner.blob { resultCard(blob) }
                    if !runner.lines.isEmpty { logPanel }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding()
            }
            .onChange(of: runner.lines.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .task {
            if entries.isEmpty {
                entries = await ModelCatalog.load().available(.chat)
                if selected == nil { selected = entries.first }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Community Bench").font(.headline)
            Text("Your device measures a fixed protocol (a fixed prompt → \(BenchRunner.maxTokens) greedy tokens, \(BenchRunner.coldRuns) cold + \(BenchRunner.warmRuns) warm) through the same on-device engine the Chat tab uses. Share the result blob on GitHub to add your device row to the community matrix.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Model", selection: $selected) {
                    ForEach(entries) { m in
                        Text("\(m.name)\(sizeSuffix(m))").tag(Optional(m))
                    }
                }
                .pickerStyle(.menu)
                .disabled(runner.running)
                Spacer()
            }
            Button {
                guard let selected else { return }
                Task { await runner.run(entry: selected) }
            } label: {
                Label(runner.running ? "Running…" : "Run benchmark", systemImage: "speedometer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(runner.running || selected == nil)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultCard(_ blob: BenchBlob) -> some View {
        let warm = blob.results.runs.filter { $0.kind == "warm" }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(blob.model.id).font(.subheadline).fontWeight(.semibold)
                    Text("\(blob.device.model_identifier) · \(blob.device.os)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f tok/s", blob.warmDecodeMedian))
                        .font(.title2).fontWeight(.bold).monospacedDigit()
                    Text("decode · median of \(warm) warm runs")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                GridRow {
                    Text("load").foregroundStyle(.secondary)
                    Text(String(format: "%.1f s", blob.results.load_s)).monospacedDigit()
                }
                if let cold = blob.coldRun {
                    GridRow {
                        Text("cold run").foregroundStyle(.secondary)
                        Text(String(format: "prefill %.1f · decode %.1f tok/s",
                                    cold.prefill_tok_s, cold.decode_tok_s)).monospacedDigit()
                    }
                }
                GridRow {
                    Text("thermal").foregroundStyle(.secondary)
                    Text("\(blob.environment.thermal_state_before) → \(blob.environment.thermal_state_after)")
                }
            }
            .font(.caption)

            HStack(spacing: 8) {
                Button {
                    BenchRunner.copyToPasteboard(runner.blobJSON)
                    copied = true
                    openURL(BenchRunner.submissionURL(blobJSON: runner.blobJSON)
                        ?? BenchRunner.templateURL)
                } label: {
                    Label("Submit on GitHub", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    BenchRunner.copyToPasteboard(runner.blobJSON)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                ShareLink(item: runner.blobJSON) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            Text("Submitting opens a GitHub issue with this blob — your device becomes a row in BENCHMARKS.md. No account data leaves the device.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(runner.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sizeSuffix(_ entry: CatalogEntry) -> String {
        guard let mb = entry.variant?.sizeMB else { return "" }
        return String(format: " (%.1f GB)", Double(mb) / 1000)
    }
}

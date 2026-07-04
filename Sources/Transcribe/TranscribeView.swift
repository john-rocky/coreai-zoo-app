import SwiftUI
import UniformTypeIdentifiers

struct TranscribeView: View {
    @State private var model = TranscribeModel()
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            header
            controls
            transcriptBox
            if !model.detectedLanguage.isEmpty {
                Text("Detected language: \(model.detectedLanguage)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .task { await model.loadCatalog() }
        .onChange(of: model.selectedEntry) { _, _ in model.selectionChanged() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { model.loadFile(url) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Picker("Model", selection: $model.selectedEntry) {
                    ForEach(model.entries) { entry in
                        Text(entry.name).tag(Optional(entry))
                    }
                }
                .fixedSize()
                .disabled(model.isBusy)

                Button(model.isSelectionLoaded ? "Loaded" : "Download & Load") { model.load() }
                    .disabled(model.isBusy || model.selectedEntry == nil || model.isSelectionLoaded)
            }
            Text(model.status.label).font(.callout).foregroundStyle(statusColor)
            if let f = model.downloadFraction {
                ProgressView(value: f).frame(maxWidth: 280)
            }
            Text(model.clipName).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Button(model.recording ? "Stop" : "Record") { model.toggleRecord() }
                    .disabled(model.isBusy)
                Button("Choose…") { showImporter = true }.disabled(model.isBusy)
                Button("Demo") { model.loadDemo() }.disabled(model.isBusy)
                Spacer()
                Button("Transcribe") { model.transcribe() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canTranscribe)
            }
        }
    }

    private var transcriptBox: some View {
        ScrollView {
            Text(model.transcript.isEmpty ? "Transcript will appear here." : model.transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(model.transcript.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .padding()
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch model.status {
        case .error: return .red
        case .ready: return .green
        default: return .secondary
        }
    }
}

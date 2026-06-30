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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { model.loadFile(url) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Transcribe").font(.title2.bold())
            Text("Whisper large-v3-turbo · 100 languages · on-device")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.status.label).font(.callout).foregroundStyle(statusColor)
            if let f = model.downloadFraction {
                ProgressView(value: f).frame(maxWidth: 280)
            }
            Text(model.clipName).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button(model.isReady ? "Whisper ready" : "Download & Load Whisper") {
                model.load()
            }
            .disabled(model.isBusy || model.isReady)

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

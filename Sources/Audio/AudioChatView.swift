// AudioChatView — audio understanding: attach a clip, ask about it, get an answer, on-device.
// Loads a Qwen2.5-Omni audio bundle as a KitAudioModel (mel → encoder → static buffer) and
// answers through a FoundationModels `LanguageModelSession`. Ported from the kit's AudioChat
// Example, reusing the zoo's own `AudioLoader` for input. macOS-only today (no iOS variant).

import CoreAIKit
import FoundationModels
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AudioChatModel {
    var status = "Pick a model and load it."
    var busy = false
    var clipName = "No audio loaded."
    var answer = ""
    var entries: [CatalogEntry] = []
    var selectedEntry: CatalogEntry?

    private var model: KitAudioModel?
    private var loadedID: String?
    private var samples: [Float]?

    /// Clip cap (s): the decoder prefills the audio tokens one step at a time, so a long clip
    /// is a long, slow prefill. The proven demo is ~4 s ≈ 100 tokens; cap for snappy answers.
    private let maxClipSeconds = 6

    var loaded: Bool { model != nil }
    var canAsk: Bool { loaded && samples != nil && !busy }

    /// Live catalog with the built-in snapshot as offline fallback.
    func loadCatalog() async {
        guard entries.isEmpty else { return }
        entries = await ModelCatalog.load().available(.audio)
        if selectedEntry == nil { selectedEntry = entries.first }
    }

    func load() {
        guard let entry = selectedEntry, !busy, loadedID != entry.id else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                status = "Loading \(entry.name)…"
                // Same gesture as the model card: the catalog id resolves the decoder +
                // encoder pair (downloaded on first use, cached afterwards).
                let m = try await KitAudioModel(catalog: entry.id) { progress in
                    Task { @MainActor in
                        self.status = "Downloading… \(Int(progress.fraction * 100))%"
                    }
                }
                self.model = m
                loadedID = entry.id
                status = "Ready — load a clip, then ask."
            } catch {
                status = "Load failed: \(error.localizedDescription)"
            }
        }
    }

    func loadFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let pcm = AudioLoader.load16kMono(url) else {
            status = "Could not decode \(url.lastPathComponent)."
            return
        }
        samples = pcm
        clipName = "\(url.lastPathComponent)  (\(String(format: "%.1f", Double(pcm.count) / 16000))s)"
        answer = ""
        status = "Audio loaded. Ask a question."
    }

    func loadDemo() {
        let pcm = AudioLoader.demoNoise()
        samples = pcm
        clipName = "Demo: white noise (4s)"
        answer = ""
        status = "Demo clip loaded. Ask a question."
    }

    func ask(_ question: String) {
        guard let model, let samples, !busy else { return }
        busy = true
        answer = ""
        let clip = Array(samples.prefix(16000 * maxClipSeconds))
        Task {
            defer { busy = false }
            do {
                status = "Encoding audio…"
                try await model.attach(samples: clip)  // mel → encoder → static buffer
                status = "Thinking… (on-device, a few seconds)"
                let session = LanguageModelSession(model: model)
                let stream = session.streamResponse(
                    to: question.isEmpty ? "What do you hear?" : question,
                    options: GenerationOptions(maximumResponseTokens: 128))
                for try await snapshot in stream { answer = snapshot.content }
                status = "Done."
            } catch {
                status = "Generation failed: \(error.localizedDescription)"
            }
        }
    }
}

struct AudioChatView: View {
    @State private var model = AudioChatModel()
    @State private var question = ""
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Picker("Model", selection: $model.selectedEntry) {
                    ForEach(model.entries) { entry in
                        Text(entry.name).tag(Optional(entry))
                    }
                }
                .fixedSize()
                .disabled(model.busy)

                Button(model.loaded ? "Loaded" : "Download & Load") { model.load() }
                    .disabled(model.busy || model.selectedEntry == nil || model.loaded)

                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
            }

            HStack {
                Button("Choose…") { showImporter = true }.disabled(model.busy || !model.loaded)
                Button("Demo") { model.loadDemo() }.disabled(model.busy || !model.loaded)
                Text(model.clipName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }

            ScrollView {
                Text(model.answer.isEmpty ? "The answer appears here." : model.answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.answer.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                TextField("Ask about the clip (blank = what do you hear?)", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.ask(question) }
                    .disabled(!model.canAsk)
                Button("Ask") { model.ask(question) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAsk)
            }

            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
        .task { await model.loadCatalog() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { model.loadFile(url) }
        }
    }
}

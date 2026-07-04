// TranscribeModel — on-device speech-to-text, catalog-driven. Pick any ASR model on the
// platform (Whisper / Nemotron everywhere, plus Qwen3-ASR / Parakeet on Mac); the app-side
// `ASRTranscriber` routes the catalog id to the right kit driver. Downloads the bundle on
// first load, then transcribes a recorded / chosen / demo clip (16 kHz mono) fully on device.

import CoreAIKit
import Foundation
import Observation

@MainActor
@Observable
final class TranscribeModel {
    enum Status: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case transcribing
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Pick a model and load it"
            case .downloading(let f): return "Downloading… \(Int(f * 100))%"
            case .loading: return "Loading…"
            case .ready: return "Ready — record, choose, or demo"
            case .transcribing: return "Transcribing…"
            case .error(let m): return "Error: \(m)"
            }
        }
    }

    var status: Status = .idle
    var clipName = "No audio loaded."
    var transcript = ""
    var detectedLanguage = ""
    var recording = false
    var entries: [CatalogEntry] = []
    var selectedEntry: CatalogEntry?

    private var transcriber: ASRTranscriber?
    private var loadedID: String?
    private var samples: [Float]?
    private let recorder = MicRecorder()

    var isBusy: Bool {
        switch status {
        case .downloading, .loading, .transcribing: return true
        default: return false
        }
    }

    var downloadFraction: Double? {
        if case .downloading(let f) = status { return f }
        return nil
    }

    var isReady: Bool { status == .ready }
    var canTranscribe: Bool { status == .ready && samples != nil }
    /// Whether the loaded model matches the current picker selection.
    var isSelectionLoaded: Bool { loadedID != nil && loadedID == selectedEntry?.id }

    /// Switching the picker to a different model makes the loaded one stale → require a reload.
    func selectionChanged() {
        if !isSelectionLoaded, status == .ready { status = .idle }
    }

    /// Live catalog with the built-in snapshot as offline fallback.
    func loadCatalog() async {
        guard entries.isEmpty else { return }
        entries = await ModelCatalog.load().available(.asr)
        if selectedEntry == nil { selectedEntry = entries.first }
    }

    /// Download (first run) + load the selected ASR model. Reloads when the picker changes.
    func load() {
        guard !isBusy, let entry = selectedEntry else { return }
        guard transcriber == nil || loadedID != entry.id else { return }
        status = .loading
        transcriber = nil
        loadedID = nil
        Task {
            do {
                let t = try await ASRTranscriber.load(catalog: entry.id) { progress in
                    Task { @MainActor in
                        self.status = progress.fraction < 1
                            ? .downloading(progress.fraction) : .loading
                    }
                }
                self.transcriber = t
                self.loadedID = entry.id
                self.status = .ready
            } catch {
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func loadFile(_ url: URL) {
        guard let pcm = AudioLoader.load16kMono(url) else {
            clipName = "Could not decode \(url.lastPathComponent)."
            return
        }
        setClip(pcm, name: "\(url.lastPathComponent)  (\(secs(pcm))s)")
    }

    func loadDemo() {
        setClip(AudioLoader.demoNoise(), name: "Demo: white noise (4s)")
    }

    func toggleRecord() {
        if recording {
            recording = false
            recorder.stop { [weak self] pcm in
                Task { @MainActor in
                    guard let self else { return }
                    if pcm.isEmpty {
                        self.clipName = "No audio captured."
                    } else {
                        self.setClip(pcm, name: "Mic clip (\(self.secs(pcm))s)")
                    }
                }
            }
        } else {
            recording = true
            clipName = "Recording… tap Stop when done."
            recorder.start { [weak self] error in
                Task { @MainActor in
                    guard let self, let error else { return }
                    self.recording = false
                    self.clipName = "Mic error: \(error.localizedDescription)"
                }
            }
        }
    }

    func transcribe() {
        guard let transcriber, let samples, status == .ready else { return }
        status = .transcribing
        transcript = ""
        detectedLanguage = ""
        Task {
            do {
                let result = try await transcriber.transcribe(samples: samples) { partial in
                    Task { @MainActor in self.transcript = partial }
                }
                self.transcript = result.text
                self.detectedLanguage = result.language
                self.status = .ready
            } catch {
                self.status = .error(error.localizedDescription)
            }
        }
    }

    private func setClip(_ pcm: [Float], name: String) {
        samples = pcm
        transcript = ""
        detectedLanguage = ""
        clipName = name
    }

    private func secs(_ pcm: [Float]) -> String {
        String(format: "%.1f", Double(pcm.count) / 16000)
    }
}

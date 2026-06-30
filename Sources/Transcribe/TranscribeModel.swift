// TranscribeModel — on-device speech-to-text with Whisper large-v3-turbo via CoreAIKit's
// KitWhisperModel. Downloads the bundle on first load, then transcribes a recorded / chosen /
// demo clip (16 kHz mono) fully on device. 100 languages, auto-detect, ≤30 s window.

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
            case .idle: return "Download Whisper to start"
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

    private var whisper: KitWhisperModel?
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

    /// Download (first run) + load the Whisper graph.
    func load() {
        guard !isBusy, whisper == nil else { return }
        status = .loading
        Task {
            do {
                let w = try await KitWhisperModel(model: .largeV3Turbo) { progress in
                    Task { @MainActor in
                        self.status = progress.fraction < 1
                            ? .downloading(progress.fraction) : .loading
                    }
                }
                self.whisper = w
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
        guard let whisper, let samples, status == .ready else { return }
        status = .transcribing
        transcript = ""
        detectedLanguage = ""
        Task {
            do {
                let result = try await whisper.transcribe(samples: samples) { partial in
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

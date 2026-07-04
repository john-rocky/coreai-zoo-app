// ASRTranscriber — app-side dispatch over the catalog's speech-to-text families. The kit's
// `KitTranscriber` routes whisper / qwen3-asr / parakeet by catalog id, but Nemotron ships its
// own streaming driver (`KitNemotronModel`) that KitTranscriber doesn't cover — so the zoo
// picks the class by id here. Both return the same `Transcription` (text + language), so the
// Transcribe tab treats every ASR model uniformly behind one picker.

import CoreAIKit

enum ASRTranscriber {
    case general(KitTranscriber)   // whisper / qwen3-asr / parakeet
    case nemotron(KitNemotronModel)  // streaming conformer-TDT

    static let nemotronID = "nemotron-3.5-asr-streaming-0.6b"

    static func load(
        catalog id: String,
        downloadProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> ASRTranscriber {
        if id == nemotronID {
            return .nemotron(
                try await KitNemotronModel(catalog: id, downloadProgress: downloadProgress))
        }
        return .general(
            try await KitTranscriber(catalog: id, downloadProgress: downloadProgress))
    }

    func transcribe(
        samples: [Float], onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> Transcription {
        switch self {
        case .general(let t):
            return try await t.transcribe(samples: samples, onPartial: onPartial)
        case .nemotron(let n):
            return try await n.transcribe(samples: samples, onPartial: onPartial)
        }
    }
}

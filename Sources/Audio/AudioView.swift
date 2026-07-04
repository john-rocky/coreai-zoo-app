// AudioView — the zoo's Audio capability tab. Groups the on-device audio features behind a
// segmented selector so the tab bar stays short: Speak (text-to-speech) and Transcribe
// (speech-to-text) everywhere, plus Music (Stable Audio) on macOS, where its catalog variant
// ships. Audio-understanding chat lands here as a further mode later.

import SwiftUI

struct AudioView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case speak = "Speak"
        case transcribe = "Transcribe"
        case music = "Music"
        case understand = "Understand"
        var id: String { rawValue }
    }

    /// Modes with a catalog variant on this platform. Music (Stable Audio) and Understand
    /// (Qwen2.5-Omni audio) are macOS-only today.
    static var modes: [Mode] {
        #if os(macOS)
        return [.speak, .transcribe, .music, .understand]
        #else
        return [.speak, .transcribe]
        #endif
    }

    @State private var mode: Mode = .speak

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Self.modes) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(10)
            Divider()
            switch mode {
            case .speak: SpeakView()
            case .transcribe: TranscribeView()
            case .music: MusicView()
            case .understand: AudioChatView()
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }
}

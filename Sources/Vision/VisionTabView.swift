// VisionTabView — the zoo's Vision capability tab. Ask (VLM: photo + question → answer) runs
// everywhere; Read (OCR: document image → markdown) appears on macOS, where Unlimited-OCR's
// catalog variant ships. With a single mode the selector is hidden, so iPhone shows the VLM
// view directly.

import SwiftUI

struct VisionView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ask = "Ask"
        case read = "Read"
        var id: String { rawValue }
    }

    /// Modes with a catalog variant on this platform. OCR (Read) is macOS-only today.
    static var modes: [Mode] {
        #if os(macOS)
        return [.ask, .read]
        #else
        return [.ask]
        #endif
    }

    @State private var mode: Mode = .ask

    var body: some View {
        VStack(spacing: 0) {
            if Self.modes.count > 1 {
                Picker("Mode", selection: $mode) {
                    ForEach(Self.modes) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(10)
                Divider()
            }
            switch mode {
            case .ask: VLChatView()
            case .read: OCRView()
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }
}

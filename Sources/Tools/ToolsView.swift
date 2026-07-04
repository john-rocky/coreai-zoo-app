// ToolsView — the zoo's Tools capability tab: on-device building blocks that aren't a plain
// chat. DiffuseChat (LLaDA masked-diffusion LM) today; semantic Search (CLIP / EmbeddingGemma)
// lands here next. macOS-only for now — its current members have no iOS catalog variant — so
// RootView only surfaces this tab on macOS. With a single member the selector is hidden.

import SwiftUI

struct ToolsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case diffuse = "DiffuseChat"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .diffuse

    var body: some View {
        VStack(spacing: 0) {
            if Mode.allCases.count > 1 {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(10)
                Divider()
            }
            switch mode {
            case .diffuse: DiffuseChatView()
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }
}

// CameraView — the zoo's Camera capability tab. Groups the on-device vision features that
// work off a live camera feed (or a photo) behind a segmented selector so the tab bar stays
// short: Depth, Detect, Action, Upscale. Only the selected mode holds a `CameraFeed`, so the
// camera stops when you switch away.

import SwiftUI

struct CameraView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case depth = "Depth"
        case detect = "Detect"
        case action = "Action"
        case upscale = "Upscale"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .depth

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(10)
            Divider()
            // `id(mode)` tears down the previous mode's view (and its CameraFeed) on switch.
            Group {
                switch mode {
                case .depth: DepthView()
                case .detect: DetectView()
                case .action: ActionView()
                case .upscale: UpscaleView()
                }
            }
            .id(mode)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }
}

// CoreAI Zoo — one on-device app for the whole Core AI model zoo. A thin SwiftUI shell over the
// shared CoreAIKit engine: each tab routes to one capability (chat, transcribe, …). New models
// reach users through CoreAIKit's live catalog without an app update.

import SwiftUI

@main
struct CoreAIZooApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            TranscribeView()
                .tabItem { Label("Transcribe", systemImage: "waveform") }
            RoadmapView()
                .tabItem { Label("More", systemImage: "square.grid.2x2") }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }
}

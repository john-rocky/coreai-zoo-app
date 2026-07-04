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
    // Capability tabs. Grouped by modality (the KICKOFF's Chat / Vision / Camera / Audio / …
    // plan) so the tab bar stays short; each tab grows as its capabilities land. Vision hosts
    // Ask (VLM) + Read (OCR, Mac); Camera hosts Depth/Detect/Action/Upscale; Audio hosts Speak
    // + Transcribe + Music + Understand (Mac). Bench is the community-funnel tab (on-device
    // tok/s → shareable blob). iPhone keeps exactly 5 tabs (Chat/Vision/Camera/Audio/Bench);
    // Tools (DiffuseChat, no iOS variant) and the More/roadmap are macOS-only, where the bar
    // has no 5-tab limit.
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            VisionView()
                .tabItem { Label("Vision", systemImage: "photo") }
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera") }
            AudioView()
                .tabItem { Label("Audio", systemImage: "waveform") }
            #if os(macOS)
            ToolsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            #endif
            BenchView()
                .tabItem { Label("Bench", systemImage: "speedometer") }
            #if os(macOS)
            RoadmapView()
                .tabItem { Label("More", systemImage: "square.grid.2x2") }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }
}

// RoadmapView — what the app covers today and what's next. Each capability is a CoreAIKit
// executor we route to from one shell; the live catalog (catalog.json in coreai-kit) is the
// single source of truth for which models appear.

import SwiftUI

struct RoadmapView: View {
    private struct Capability: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
        let phase: String
    }

    private let items: [Capability] = [
        .init(title: "Chat",
              detail: "Qwen3.5, LFM2.5, Granite, MiniCPM5, Nanbeige… (Mac adds 27B–35B)",
              icon: "bubble.left.and.bubble.right", phase: "Live"),
        .init(title: "Vision (VLM)",
              detail: "Qwen3-VL 2B/4B, Holo2, MiniCPM-V — ask about a photo",
              icon: "photo", phase: "Live"),
        .init(title: "Speech (TTS)",
              detail: "VoxCPM, Kokoro — text to speech",
              icon: "speaker.wave.2", phase: "Live"),
        .init(title: "Transcribe",
              detail: "Whisper large-v3-turbo (Qwen3-ASR, Parakeet next)",
              icon: "waveform", phase: "Live"),
        .init(title: "Camera",
              detail: "Depth Anything 3 · RF-DETR / YOLOX · AdcSR ×4 · V-JEPA 2 action",
              icon: "camera.metering.center.weighted", phase: "Live"),
        .init(title: "Tools",
              detail: "DiffuseChat (LLaDA) live on Mac · semantic search (CLIP / EmbeddingGemma) next",
              icon: "wrench.and.screwdriver", phase: "Mac"),
        .init(title: "Music & OCR",
              detail: "Stable Audio + Unlimited-OCR live on Mac · Qwen2.5-Omni audio next",
              icon: "music.note", phase: "Mac"),
    ]

    var body: some View {
        NavigationStack {
            List(items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.icon).font(.title3).frame(width: 30)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.phase)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(badgeColor(item.phase), in: Capsule())
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("CoreAI Zoo")
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func badgeColor(_ phase: String) -> Color {
        switch phase {
        case "Live": return .green.opacity(0.2)
        case "Mac": return .blue.opacity(0.2)
        default: return .secondary.opacity(0.15)
        }
    }
}

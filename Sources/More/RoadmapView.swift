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
        .init(title: "Chat & VLM",
              detail: "Gemma 4, Qwen3.5, LFM2.5, Granite, BitCPM, Qwen3-VL, Holo2…",
              icon: "bubble.left.and.bubble.right", phase: "Live"),
        .init(title: "Transcribe",
              detail: "Whisper large-v3-turbo (Qwen3-ASR, Parakeet next)",
              icon: "waveform", phase: "Live"),
        .init(title: "Speech (TTS)",
              detail: "VoxCPM, Kokoro — text to speech",
              icon: "speaker.wave.2", phase: "Phase 2"),
        .init(title: "Depth",
              detail: "Depth Anything 3 — photo & live camera",
              icon: "camera.metering.center.weighted", phase: "Phase 2"),
        .init(title: "Detection",
              detail: "RF-DETR — real-time object detection, no NMS",
              icon: "viewfinder", phase: "Phase 2"),
        .init(title: "Super-Resolution",
              detail: "AdcSR ×4",
              icon: "wand.and.stars", phase: "Phase 2"),
        .init(title: "Image / Doc",
              detail: "OCR, segmentation, semantic search (CLIP / embeddings)",
              icon: "doc.text.viewfinder", phase: "Phase 2"),
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
                        .background(
                            item.phase == "Live"
                                ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15),
                            in: Capsule())
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("CoreAI Zoo")
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}

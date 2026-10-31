import CoreAIKitUI
import Foundation
import Observation

@MainActor
@Observable
final class ChatModel {
    enum Status: Equatable {
        case idle
        case downloading(Double)
        case loading
        case warming
        case ready
        case generating
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Pick a model"
            case .downloading(let f): return "Downloading… \(Int(f * 100))%"
            case .loading: return "Loading…"
            case .warming: return "Warming up…"
            case .ready: return "Ready"
            case .generating: return "Generating…"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    var status: Status = .idle
    var bubbles: [ChatBubble] = []
    var stats = GenerationStats()
    var entries: [CatalogEntry] = []
    var selectedEntry: CatalogEntry?
    /// Reasoning on/off for thinking models (catalog `thinking: true`). Off renders the closed
    /// think block, so the whole response budget goes to the visible answer.
    var thinkingEnabled = true

    private var session: ChatSession?

    /// The toggle only means something on models whose template honours it.
    var showThinkingToggle: Bool { selectedEntry?.thinking == true }

    /// Why the selected model has no bundle for this device (an iPhone of another generation
    /// than the one its iPhone files were compiled for), from the catalog alone; nil otherwise.
    var unavailableReason: String? { selectedEntry?.unavailableReason }

    var isBusy: Bool {
        switch status {
        case .downloading, .loading, .warming, .generating: return true
        default: return false
        }
    }

    var downloadFraction: Double? {
        if case .downloading(let f) = status { return f }
        return nil
    }

    /// Live catalog with the built-in snapshot as offline fallback (`ZooCatalog`). The first
    /// model this device can run is selected.
    func loadCatalog() async {
        guard entries.isEmpty else { return }
        entries = await ZooCatalog.load().available(.chat)
        if selectedEntry == nil {
            selectedEntry = entries.first { $0.unavailableReason == nil } ?? entries.first
        }
    }

    @discardableResult
    func load() -> Task<Void, Never>? {
        guard !isBusy, unavailableReason == nil, let entry = selectedEntry,
            let model = entry.modelID
        else { return nil }
        status = .loading
        bubbles = []
        session = nil
        var config = ChatSession.Configuration()
        // The variant's own engine hint when it names one: LFM3 1.7B's iPhone bundle is the
        // static Neural Engine form while its entry's "pipelined" is the Mac bundle's.
        config.engineVariant = Self.engineVariant(for: entry.resolvedEngine)
        // 2.0.1: answers were cut at the kit's 2048-token default — thinking models spend most
        // of it inside <think>. Let every turn run to what the bundle's context leaves after
        // the prompt (the session clamps Int.max to max_context_length - prompt).
        config.maxResponseTokens = Int.max
        config.enableThinking = thinkingEnabled ? nil : false
        return Task {
            do {
                let session = try await ChatSession(model: model, configuration: config) { progress in
                    Task { @MainActor in
                        self.status = progress.fraction < 1
                            ? .downloading(progress.fraction) : .loading
                    }
                }
                self.status = .warming
                try await session.prewarm()
                self.session = session
                self.stats = await session.stats
                self.status = .ready
            } catch {
                self.status = .error(error.localizedDescription)
            }
        }
    }

    /// Map the catalog's optional engine hint to an EngineVariant. Zoo decode-pipelined ports
    /// carry "sequential" (the generic pipelined path SIGTRAPs on them); official-recipe bundles
    /// leave it nil → .auto (the runtime picks the fastest compatible engine).
    static func engineVariant(for hint: String?) -> EngineVariant {
        switch hint {
        case "sequential": return .sequential
        case "pipelined": return .pipelined
        case "static-shape": return .staticShape
        default: return .auto
        }
    }

    @discardableResult
    func send(_ text: String) -> Task<Void, Never>? {
        guard let session, status == .ready else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        bubbles.append(ChatBubble(role: .user, content: trimmed))
        bubbles.append(ChatBubble(role: .assistant, isStreaming: true))
        status = .generating

        return Task {
            do {
                await session.setThinking(thinkingEnabled ? nil : false)
                for try await event in await session.streamResponse(to: trimmed) {
                    switch event {
                    case .response(let delta):
                        bubbles[bubbles.count - 1].content += delta
                    case .thinking(let delta):
                        bubbles[bubbles.count - 1].thinking += delta
                    case .stats(let s):
                        stats = s
                    case .complete:
                        break
                    }
                }
            } catch {
                status = .error(error.localizedDescription)
            }
            bubbles[bubbles.count - 1].isStreaming = false
            if status == .generating { status = .ready }
        }
    }

    func stop() {
        Task { await session?.cancelGeneration() }
    }

    func newChat() {
        guard let session else { return }
        bubbles = []
        Task { await session.reset() }
    }

    /// `newChat()`, awaited (the scripted run starts every question from an empty history).
    func resetChat() async {
        bubbles = []
        await session?.reset()
    }

    /// The loaded bundle's context length and this turn's stats, for the scripted run.
    var sessionContextLength: Int? {
        get async { await session?.maxContextLength }
    }
}

// BenchRunner — the Bench tab's measurement core. Unlike the CoreAIChat reference (which drove
// a forked EngineFactory with raw token ids), the zoo measures through the SAME thin kit
// `ChatSession` its Chat tab uses — so the number is the zoo app's real engine path, not a
// separate harness. That means a NEW protocol: `zoo-chat-v1`. It can't reproduce pb-random-v1's
// raw-token prefill (the kit surface is text-in/stats-out), so its decode tok/s is comparable
// across zoo submissions but not byte-identical to the pb-random-v1 matrix.
//
// Protocol zoo-chat-v1 (baked into the blob; the aggregator matches it exactly):
//   fixed text prompt → 256 greedy tokens (temperature nil), S=1 prefill
//   (COREAI_CHUNK_THRESHOLD=1), 1 cold + 3 warm runs, `reset()` before each run so every run is
//   a full prefill (the session's cross-turn KV reuse would otherwise skip warm-run prefill).
//   Per run: prefill_tok_s = promptTokens / ttft, decode_tok_s = GenerationStats.tokensPerSecond
//   (32-token rolling window = steady-state decode).

import CoreAIKitUI
import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct BenchBlob: Codable {
    var schema_version: Int
    var kind: String  // "coreai-community-bench"

    struct Device: Codable {
        var model_identifier: String  // "iPhone17,1" / "Mac15,3"
        var os: String                // "iOS 27.0"
        var memory_gb: Double
    }
    struct App: Codable {
        var version: String
        var build: String
    }
    struct Model: Codable {
        var id: String
        var hf_repo: String
        var bundle: String            // catalog variant path
        var engine_hint: String       // catalog engine hint ("pipelined" / "auto" / …)
    }
    struct BenchProtocol: Codable {
        var name: String              // "zoo-chat-v1"
        var prompt: String            // the exact fixed prompt (self-describing)
        var max_tokens: Int
        var temperature: Double       // 0 = greedy
        var chunk_threshold: Int
        var cold_runs: Int
        var warm_runs: Int
        var surface: String           // "kit-chatsession" — how it was measured
    }
    struct Environment: Codable {
        var thermal_state_before: String
        var thermal_state_after: String
        var low_power_mode: Bool
    }
    struct Run: Codable {
        var kind: String              // "cold" | "warm"
        var prompt_tokens: Int
        var ttft_s: Double
        var prefill_tok_s: Double
        var decode_tok_s: Double
        var gen_tokens: Int
        var thermal_state_end: String
    }
    struct Results: Codable {
        var load_s: Double
        var runs: [Run]
    }

    var device: Device
    var app: App
    var model: Model
    var benchProtocol: BenchProtocol
    var environment: Environment
    var results: Results

    enum CodingKeys: String, CodingKey {
        case schema_version, kind, device, app, model
        case benchProtocol = "protocol"
        case environment, results
    }

    var warmDecodeMedian: Double {
        let warm = results.runs.filter { $0.kind == "warm" }.map(\.decode_tok_s).sorted()
        return warm.isEmpty ? 0 : warm[warm.count / 2]
    }
    var coldRun: Run? { results.runs.first { $0.kind == "cold" } }
}

@MainActor
@Observable
final class BenchRunner {
    var lines: [String] = []
    var running = false
    var blob: BenchBlob?
    var blobJSON = ""

    // Fixed protocol (v1). Changing any of these requires a new protocol name — the
    // aggregator rejects blobs whose protocol block doesn't match exactly.
    static let protocolName = "zoo-chat-v1"
    static let maxTokens = 256
    static let coldRuns = 1
    static let warmRuns = 3
    static let prompt =
        "Explain, in detail, how a transformer language model generates text one token at a "
        + "time. Cover attention, the KV cache, and why the decode phase is bound by memory "
        + "bandwidth rather than compute. Write several paragraphs."

    private var downloadLastPct = -10

    private func add(_ line: String) { lines.append(line) }

    func run(entry: CatalogEntry) async {
        guard !running else { return }
        running = true
        defer { running = false }
        lines = []
        blob = nil
        blobJSON = ""

        let thermalBefore = Self.thermalString(ProcessInfo.processInfo.thermalState)
        // S=1 prefill contract (the pipelined decode-only graphs need it; the catalog hint
        // already drops the chunk threshold on load — set the env too for parity and record).
        if getenv("COREAI_CHUNK_THRESHOLD") == nil { setenv("COREAI_CHUNK_THRESHOLD", "1", 1) }
        let chunkThreshold = getenv("COREAI_CHUNK_THRESHOLD").map { Int(String(cString: $0)) ?? -1 } ?? -1

        add("loading \(entry.name)…")
        do {
            var cfg = ChatSession.Configuration()
            cfg.temperature = nil  // greedy → deterministic decode
            cfg.maxResponseTokens = Self.maxTokens

            downloadLastPct = -10
            let loadStart = ContinuousClock.now
            let session = try await ChatSession(catalog: entry.id, configuration: cfg) {
                progress in
                Task { @MainActor in
                    let pct = Int(progress.fraction * 100)
                    if pct >= self.downloadLastPct + 10 {
                        self.downloadLastPct = pct
                        self.add("downloading… \(pct)%")
                    }
                }
            }
            let loadS = Self.seconds(since: loadStart)
            add(String(format: "loaded in %.1fs — running %d cold + %d warm",
                       loadS, Self.coldRuns, Self.warmRuns))

            var runs: [BenchBlob.Run] = []
            for i in 0..<(Self.coldRuns + Self.warmRuns) {
                let kind = i < Self.coldRuns ? "cold" : "warm"
                await session.reset()  // full prefill each run — no cross-turn KV reuse
                for try await event in await session.streamResponse(to: Self.prompt) {
                    _ = event  // drain; final numbers read from session.stats below
                }
                let s = await session.stats
                let ttft = s.ttftSeconds ?? 0
                let prefill = ttft > 0 ? Double(s.promptTokens) / ttft : 0
                let decode = s.tokensPerSecond ?? 0
                runs.append(BenchBlob.Run(
                    kind: kind, prompt_tokens: s.promptTokens, ttft_s: round2(ttft),
                    prefill_tok_s: round1(prefill), decode_tok_s: round1(decode),
                    gen_tokens: s.generatedTokens,
                    thermal_state_end: Self.thermalString(ProcessInfo.processInfo.thermalState)))
                add(String(format: "RUN %d (%@) prefill=%.1f decode=%.1f tok/s · %d tokens",
                           i + 1, kind, prefill, decode, s.generatedTokens))
            }

            let info = Bundle.main.infoDictionary
            let result = BenchBlob(
                schema_version: 1,
                kind: "coreai-community-bench",
                device: Self.device(),
                app: BenchBlob.App(
                    version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
                    build: info?["CFBundleVersion"] as? String ?? "unknown"),
                model: BenchBlob.Model(
                    id: entry.id, hf_repo: entry.repo,
                    bundle: entry.variant?.path ?? "", engine_hint: entry.engine ?? "auto"),
                benchProtocol: BenchBlob.BenchProtocol(
                    name: Self.protocolName, prompt: Self.prompt, max_tokens: Self.maxTokens,
                    temperature: 0, chunk_threshold: chunkThreshold,
                    cold_runs: Self.coldRuns, warm_runs: Self.warmRuns, surface: "kit-chatsession"),
                environment: BenchBlob.Environment(
                    thermal_state_before: thermalBefore,
                    thermal_state_after: Self.thermalString(ProcessInfo.processInfo.thermalState),
                    low_power_mode: ProcessInfo.processInfo.isLowPowerModeEnabled),
                results: BenchBlob.Results(load_s: round1(loadS), runs: runs))

            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            blobJSON = String(data: (try? enc.encode(result)) ?? Data(), encoding: .utf8) ?? "{}"
            blob = result
            add(String(format: "STATS BENCH model=%@ load=%.1fs warm_decode_med=%.1f tok/s",
                       entry.id, loadS, result.warmDecodeMedian))
        } catch {
            add("ERROR \(error.localizedDescription)")
        }
    }

    // MARK: - Submission

    /// Prefilled bench-result issue on the zoo repo; nil when the blob would overflow the URL
    /// (the caller falls back to `templateURL` with the blob on the clipboard).
    static func submissionURL(blobJSON: String) -> URL? {
        var comps = URLComponents(string: "https://github.com/john-rocky/coreai-model-zoo/issues/new")!
        comps.queryItems = [
            URLQueryItem(name: "template", value: "bench-result.yml"),
            URLQueryItem(name: "blob", value: "```json\n\(blobJSON)\n```"),
        ]
        guard let url = comps.url, url.absoluteString.count < 7500 else { return nil }
        return url
    }

    static let templateURL = URL(
        string: "https://github.com/john-rocky/coreai-model-zoo/issues/new?template=bench-result.yml")!

    static func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Helpers

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let c = start.duration(to: .now).components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    static func thermalString(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func device() -> BenchBlob.Device {
        let memGB = (Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 * 10).rounded() / 10
        return BenchBlob.Device(
            model_identifier: machineIdentifier(),
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            memory_gb: memGB)
    }

    private static func machineIdentifier() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
        #else
        var sysinfo = utsname()
        uname(&sysinfo)
        let id = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let bytes = raw.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
        return id
        #endif
    }
}

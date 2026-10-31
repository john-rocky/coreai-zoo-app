// ChatScript — a scripted run of the Chat tab, for checking a model on a device end to end. The
// launch argument `-ZooChatScript` (the JSON, or a file holding it, absolute or relative to
// Documents) names a catalog id, thinking on or off, and the questions. The tab selects that model,
// loads it the way its Load button does, sends each question in a new chat, and writes one JSON
// line per question to <out>.jsonl (absolute, or in Documents): the bubble's answer and thinking
// as the Chat view shows them (its own ChatModel, started at launch), and the turn's stats. A "done" line ends the file, and
// `"exit": true` quits the app after it, so a run started from a shell returns when the script
// does. The value is read from the launch arguments alone, never from saved settings, so no
// screen in the app can start it.

import CoreAIKit
import Foundation
import os
#if os(iOS) && canImport(CoreAI)
import CoreAI
#endif

struct ChatScript: Decodable {
    struct Question: Decodable {
        let qi: Int
        let label: String?
        let prompt: String
    }

    let id: String
    let thinking: Bool
    let questions: [Question]
    let out: String
    let exit: Bool?

    private static let log = Logger(subsystem: "com.daisukemajima.coreaizoo", category: "chat-script")

    /// Starts the run when the launch arguments ask for one; otherwise does nothing.
    static func startIfRequested() {
        guard let argument = ZooCatalog.launchArgument("ZooChatScript") else { return }
        Task { @MainActor in
            let model = ChatModel()
            await model.loadCatalog()
            await runScript(argument, model)
        }
    }

    @MainActor
    private static func runScript(_ argument: String, _ model: ChatModel) async {
        let script: ChatScript
        do {
            script = try JSONDecoder().decode(ChatScript.self, from: ZooCatalog.data(argument))
        } catch {
            log.error("-ZooChatScript: \(error.localizedDescription, privacy: .public)")
            return
        }
        await script.run(model)
        if script.exit == true { Darwin.exit(0) }
    }

    @MainActor
    private func run(_ model: ChatModel) async {
        let output = out.hasPrefix("/")
            ? URL(fileURLWithPath: "\(out).jsonl")
            : URL.documentsDirectory.appendingPathComponent("\(out).jsonl")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let start = ContinuousClock.now
        func write(_ record: [String: Any]) {
            guard let line = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                let handle = try? FileHandle(forWritingTo: output)
            else { return }
            handle.seekToEndOfFile()
            handle.write(line + Data("\n".utf8))
            try? handle.close()
        }

        write(["kind": "probe", "catalog": ZooCatalog.source, "device": Self.device()])
        guard let entry = model.entries.first(where: { $0.id == id }) else {
            write(["kind": "done", "error": "no chat entry '\(id)' in the \(ZooCatalog.source) catalog"])
            return
        }
        model.selectedEntry = entry
        model.thinkingEnabled = thinking
        write(header(entry))
        if let reason = entry.unavailableReason {
            write(["kind": "done", "error": "unavailable: \(reason)"])
            return
        }

        let loadStart = ContinuousClock.now
        await model.load()?.value
        let loadS = Self.seconds(since: loadStart)
        var load: [String: Any] = ["kind": "load", "status": model.status.label, "load_s": loadS,
                                   "after": Self.device()]
        load["subtrees_on_disk"] = Self.subtreesOnDisk(entry)
        write(load)
        guard model.status == .ready else {
            write(["kind": "done", "error": model.status.label])
            return
        }

        for question in questions {
            await model.resetChat()
            let before = Self.device()
            await model.send(question.prompt)?.value
            let bubble = model.bubbles.last
            let stats = model.stats
            let context = await model.sessionContextLength
            let budget = context.map { max(1, $0 - stats.promptTokens) }
            let response = bubble?.content ?? ""
            var record: [String: Any] = [
                "kind": "q", "qi": question.qi, "label": question.label ?? "",
                "prompt": question.prompt, "response": response,
                "thinking": bubble?.thinking ?? "",
                "prompt_tokens": stats.promptTokens, "cached_prompt_tokens": stats.cachedPromptTokens,
                "generated_tokens": stats.generatedTokens, "footprint_bytes": Int(stats.footprintBytes),
                "think_markers_in_response": ["<think>", "</think>"].reduce(0) {
                    $0 + response.components(separatedBy: $1).count - 1
                },
                "before": before, "after": Self.device(), "status": model.status.label,
            ]
            if let budget {
                record["max_tokens"] = budget
                record["stop"] = stats.generatedTokens < budget ? "stop_token" : "max_tokens"
            }
            if let context { record["context_length"] = context }
            if let ttft = stats.ttftSeconds { record["ttft_s"] = ttft }
            if let tps = stats.tokensPerSecond { record["tok_s_decode"] = tps }
            write(record)
            if case .error = model.status { break }
        }
        write(["kind": "done", "n": questions.count, "elapsed_s": Self.seconds(since: start),
               "status": model.status.label])
        Self.log.info("chat script \(out, privacy: .public) done")
    }

    @MainActor
    private func header(_ entry: CatalogEntry) -> [String: Any] {
        let info = Bundle.main.infoDictionary
        var h: [String: Any] = [
            "kind": "header", "script": out, "catalog": ZooCatalog.source,
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "",
            "app_build": info?["CFBundleVersion"] as? String ?? "",
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "id": entry.id, "name": entry.name, "thinking": thinking,
            "platform_key": CatalogEntry.platformKey,
            "variant_path": entry.variant?.path ?? "",
            "variant_key": entry.variantKey ?? CatalogEntry.platformKey,
            "resolved_engine": entry.resolvedEngine ?? "",
            "engine_variant": ChatModel.engineVariant(for: entry.resolvedEngine).rawValue,
            "revision": entry.revision ?? "",
            "unavailable_reason": entry.unavailableReason ?? "",
            "device": Self.device(),
        ]
        #if os(iOS) && canImport(CoreAI)
        if #available(iOS 27, *) { h["arch"] = AIModel.deviceArchitectureName }
        #endif
        return h
    }

    /// The subtrees of this entry's pinned revision in the store after the load (`ios-h19p` on an
    /// iPhone 18 Pro for a repo with no `ios/`), and their size on disk.
    private static func subtreesOnDisk(_ entry: CatalogEntry) -> [String: Int64] {
        guard let revision = entry.revision else { return [:] }
        let root = ModelStore.default.directory
            .appendingPathComponent(entry.repo, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
        var out: [String: Int64] = [:]
        for child in DownloadsModel.children(of: root) {
            out[child.lastPathComponent] = DownloadsModel.size(of: child)
        }
        return out
    }

    private static func device() -> [String: Any] {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let free = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        return [
            "machine": String(decoding: machine.prefix { $0 != 0 }, as: UTF8.self),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "thermal": thermal,
            "footprint_bytes": Int(footprint()),
            "free_bytes": free.map { Int($0) } ?? -1,
        ]
    }

    /// The process's physical footprint, the number iOS's memory limit is held against.
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

// SmokeScript — a scripted pass over the Bench, Speak and Downloads tabs' models, for checking a
// build on a Mac or a device without driving its windows. The launch argument `-ZooSmoke` (the
// JSON, or a file holding it) can name a catalog id to bench (BenchRunner, the Bench tab's runner),
// a voice and a sentence to synthesize (KitSpeaker, as the Speak tab loads it; not played), and an
// output path. It writes <out>.json: the catalog source, the downloaded-models list as the Downloads
// sheet builds it, every voice's reason from KitSpeaker.unavailableReason(for:), the bench blob
// and log, and the utterance's length. `"exit": true` quits the app after it. The value is read
// from the launch arguments alone, never from saved settings, so no screen in the app can start it.

import CoreAIKit
import Foundation
import os

struct SmokeScript: Decodable {
    struct Speak: Decodable {
        let id: String
        let text: String
    }

    let bench: String?
    let speak: Speak?
    let out: String
    let exit: Bool?

    private static let log = Logger(subsystem: "com.daisukemajima.coreaizoo", category: "smoke-script")

    /// Starts the pass when the launch arguments ask for one; otherwise does nothing.
    static func startIfRequested() {
        guard let argument = ZooCatalog.launchArgument("ZooSmoke") else { return }
        Task { @MainActor in
            do {
                let script = try JSONDecoder().decode(SmokeScript.self, from: ZooCatalog.data(argument))
                await script.run()
                if script.exit == true { Darwin.exit(0) }
            } catch {
                log.error("-ZooSmoke: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private func run() async {
        let catalog = await ZooCatalog.load()
        var report: [String: Any] = ["catalog": ZooCatalog.source, "started": Date().description]
        func save() {
            let url = out.hasPrefix("/")
                ? URL(fileURLWithPath: "\(out).json")
                : URL.documentsDirectory.appendingPathComponent("\(out).json")
            if let data = try? JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url)
            }
        }

        let downloads = DownloadsModel()
        await downloads.refresh()
        report["downloads_before"] = downloads.repos.map { ["title": $0.title, "bytes": $0.bytes] }
        report["voices"] = catalog.available(.tts).map {
            ["id": $0.id, "reason": KitSpeaker.unavailableReason(for: $0) ?? ""]
        }
        save()

        if let id = bench {
            if let entry = catalog.available(.chat).first(where: { $0.id == id }) {
                let runner = BenchRunner()
                await runner.run(entry: entry)
                report["bench"] = ["id": id, "blob": runner.blobJSON, "lines": runner.lines]
            } else {
                report["bench"] = ["id": id, "error": "not a chat entry of the \(ZooCatalog.source) catalog"]
            }
            save()
        }

        if let speak {
            var row: [String: Any] = ["id": speak.id, "text": speak.text]
            if let entry = catalog.available(.tts).first(where: { $0.id == speak.id }) {
                row["reason"] = KitSpeaker.unavailableReason(for: entry) ?? ""
                do {
                    let start = ContinuousClock.now
                    let speaker = try await KitSpeaker(catalog: entry.id)
                    row["load_s"] = Self.seconds(since: start)
                    let synth = ContinuousClock.now
                    let audio = try await speaker.synthesize(speak.text)
                    row["synthesize_s"] = Self.seconds(since: synth)
                    row["audio_seconds"] = audio.seconds
                    row["sample_rate"] = audio.sampleRate
                } catch {
                    row["error"] = error.localizedDescription
                }
            } else {
                row["error"] = "not a voice of the \(ZooCatalog.source) catalog"
            }
            report["speak"] = row
            save()
        }

        await downloads.refresh()
        report["downloads_after"] = downloads.repos.map { ["title": $0.title, "bytes": $0.bytes] }
        report["done"] = Date().description
        save()
        Self.log.info("smoke script \(out, privacy: .public) done")
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

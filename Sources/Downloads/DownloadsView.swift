// DownloadsView — the models this app has downloaded, their size on disk, and a way to delete
// them. One row per Hugging Face repo in CoreAIKit's model store: a catalog model can span
// several subtrees of its repo (graphs, tokenizer, host glue) and older revisions, and all of
// them sit under <store>/<org>/<name>/. Rows are named by the catalog entries of that repo.
// Opened from the button next to the Chat, Camera and Audio pickers.

import CoreAIKit
import SwiftUI

struct DownloadedRepo: Identifiable, Sendable {
    let url: URL
    let title: String
    let bytes: Int64
    var id: URL { url }
}

@MainActor
@Observable
final class DownloadsModel {
    var repos: [DownloadedRepo] = []
    var loading = true
    var errorText: String?

    var totalBytes: Int64 { repos.reduce(0) { $0 + $1.bytes } }

    func refresh() async {
        let entries = await ZooCatalog.load().available()
        let root = ModelStore.default.directory
        repos = await Task.detached { Self.scan(root: root, entries: entries) }.value
        loading = false
    }

    /// Deletes the repo's files and this app's compile-cache entries for its graphs. A model
    /// that is loaded right now keeps running; it downloads again the next time it is loaded.
    func delete(_ repo: DownloadedRepo) {
        do {
            let hashes = Self.graphHashes(under: repo.url)
            try FileManager.default.removeItem(at: repo.url)
            Self.removeCompileCaches(named: hashes)
            repos.removeAll { $0.id == repo.id }
        } catch {
            errorText = error.localizedDescription
        }
    }

    nonisolated static func scan(root: URL, entries: [CatalogEntry]) -> [DownloadedRepo] {
        var found: [DownloadedRepo] = []
        for org in children(of: root) {
            for repo in children(of: org) {
                let id = "\(org.lastPathComponent)/\(repo.lastPathComponent)"
                let names = entries.filter { $0.repo == id }.map(\.name)
                let bytes = size(of: repo)
                guard bytes > 0 else { continue }
                found.append(DownloadedRepo(
                    url: repo,
                    title: names.isEmpty ? repo.lastPathComponent : names.joined(separator: ", "),
                    bytes: bytes))
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    nonisolated static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    /// Bytes on disk under `url`, the hidden staging directory of an interrupted download included.
    nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys))
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// The `main.hash` of every graph bundle under `url`, as hex: the name of that bundle's
    /// entry in Core AI's compile cache.
    nonisolated static func graphHashes(under url: URL) -> Set<String> {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        else { return [] }
        var hashes: Set<String> = []
        for case let file as URL in files where file.lastPathComponent == "main.hash" {
            if let data = try? Data(contentsOf: file), data.count == 32 {
                hashes.insert(data.map { String(format: "%02x", $0) }.joined())
            }
        }
        return hashes
    }

    /// Core AI keeps each graph it specialized at
    /// Caches/coreai-cache/<OS build>/<process name>/<main.hash hex>/, roughly the bundle's size
    /// again. Only this process's entries with these exact hashes are removed.
    nonisolated static func removeCompileCaches(named hashes: Set<String>) {
        guard !hashes.isEmpty else { return }
        let fm = FileManager.default
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("coreai-cache", isDirectory: true)
        let process = ProcessInfo.processInfo.processName
        for build in children(of: cache) {
            let mine = build.appendingPathComponent(process, isDirectory: true)
            for hash in hashes {
                try? fm.removeItem(at: mine.appendingPathComponent(hash, isDirectory: true))
            }
        }
    }
}

struct DownloadsView: View {
    @State private var model = DownloadsModel()
    @State private var pending: DownloadedRepo?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.repos.isEmpty, !model.loading {
                        Text("No models downloaded yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.repos) { repo in
                        HStack {
                            Text(repo.title)
                            Spacer()
                            Text(Self.format(repo.bytes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                pending = repo
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(repo.title)")
                        }
                    }
                } footer: {
                    if !model.repos.isEmpty {
                        Text("\(Self.format(model.totalBytes)) in total. A deleted model downloads again the next time you load it.")
                    }
                }
                if let errorText = model.errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Downloaded models")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this model?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                presenting: pending
            ) { repo in
                Button("Delete", role: .destructive) { model.delete(repo) }
            } message: { repo in
                Text("\(repo.title) (\(Self.format(repo.bytes))) is removed from this device.")
            }
        }
        .task { await model.refresh() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Opens the downloaded-models list.
struct DownloadsButton: View {
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "externaldrive")
        }
        .accessibilityLabel("Downloaded models")
        .sheet(isPresented: $showing) { DownloadsView() }
    }
}

extension CatalogEntry {
    /// Whether this platform's variant is already in the model store (no network involved).
    var isDownloaded: Bool {
        modelID.flatMap { ModelStore.default.localURL(for: $0) } != nil
    }

    /// "Download" plus the size the catalog states for this platform.
    var downloadTitle: String {
        guard let mb = variant?.sizeMB else { return "Download" }
        return "Download \(DownloadsView.format(Int64(mb) * 1_000_000))"
    }
}

// ZooCatalog — the model catalog the Chat, Bench and Downloads views read. It is CoreAIKit's live
// catalog with the built-in snapshot as offline fallback (`ModelCatalog.load()`), unless the app
// was launched with `-ZooCatalog builtin` (the snapshot this build's kit was packaged with),
// `-ZooCatalog <file>` (a catalog JSON, absolute or relative to Documents) or the JSON itself.
// That is how a catalog row is checked on a device before it reaches the live catalog. The value
// is read from the launch arguments alone, never from saved settings, so no screen in the app can
// set it.

import CoreAIKit
import Foundation
import os

enum ZooCatalog {
    private static let log = Logger(subsystem: "com.daisukemajima.coreaizoo", category: "catalog")

    /// The launch argument's value, or nil on an ordinary launch.
    static var override: String? { launchArgument("ZooCatalog") }

    /// The value after `-<name>` in the launch arguments, as given. The raw arguments, not
    /// UserDefaults' argument domain: that domain parses a value as a property list and drops one
    /// it cannot parse, a JSON object among them.
    static func launchArgument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(i + 1)
        else { return nil }
        return arguments[i + 1]
    }

    /// Where the catalog came from, for logs: "live", "builtin", "inline" or the file's path.
    static var source: String {
        guard let override else { return "live" }
        return override.hasPrefix("{") ? "inline" : override
    }

    static func load() async -> ModelCatalog {
        guard let override else { return await ModelCatalog.load() }
        if override == "builtin" { return .builtin }
        do {
            return try JSONDecoder().decode(ModelCatalog.self, from: try data(override))
        } catch {
            // An empty catalog, not the live one: a check that names a catalog must not quietly
            // run against something else.
            log.error("-ZooCatalog: \(error.localizedDescription, privacy: .public)")
            return ModelCatalog(version: ModelCatalog.builtin.version, models: [])
        }
    }

    /// A launch argument's JSON: the value itself when it is a JSON object, else the file it names
    /// (absolute, or relative to Documents).
    static func data(_ value: String) throws -> Data {
        if value.hasPrefix("{") { return Data(value.utf8) }
        let url = value.hasPrefix("/")
            ? URL(fileURLWithPath: value) : URL.documentsDirectory.appendingPathComponent(value)
        return try Data(contentsOf: url)
    }
}

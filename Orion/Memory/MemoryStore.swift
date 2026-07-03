import Foundation

/// File-based CRUD over `MemoryEntry` instances.
///
/// Each entry is one JSON file at
/// `~/Library/Application Support/Orion/memory/<uuid>.json`.
/// One-file-per-entry mirrors how the global Claude memory system
/// works — easy to inspect, edit, or delete from Finder, easy to
/// back up, and atomic writes don't risk corrupting other entries.
///
/// All public methods are main-thread safe (operations are
/// fast: 0–N small JSON files, no embeddings touched here). Disk
/// I/O is synchronous and intentionally so — cleaner than threading
/// every list/save/delete through a dispatch queue when the dataset
/// is bounded by what one human can read in a Settings pane.
enum MemoryStore {

    /// Notification fired whenever the store changes (save, delete,
    /// clear). The system-prompt builder and Settings UI both listen
    /// so they refresh without polling.
    static let didChangeNotification = Notification.Name("OrionMemoryStoreDidChange")

    // MARK: - Reading

    /// All entries on disk, sorted: pinned first, then by kind sortOrder,
    /// then by most-recently-updated. Empty list when the directory
    /// doesn't exist yet (first launch, never extracted anything).
    static func all() -> [MemoryEntry] {
        guard let dir = directoryURL() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let entries = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MemoryEntry? in
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(MemoryEntry.self, from: data) else {
                    return nil
                }
                return decoded
            }
        return entries.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            if lhs.kind.sortOrder != rhs.kind.sortOrder { return lhs.kind.sortOrder < rhs.kind.sortOrder }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// True when the user has at least one durable memory recorded.
    static var hasAny: Bool { !all().isEmpty }

    // MARK: - Writing

    /// Save `entry`, applying the sensitivity filter unless explicitly
    /// bypassed (e.g. when the user is editing an existing entry from
    /// the Settings pane and we trust their judgment).
    @discardableResult
    static func save(_ entry: MemoryEntry, bypassSensitivityFilter: Bool = false) -> SensitivityFilter.Decision {
        if !bypassSensitivityFilter {
            let decision = SensitivityFilter.evaluate(entry)
            if case .reject = decision { return decision }
        }

        guard let dir = directoryURL() else { return .reject(reason: "No app support directory") }
        let url = dir.appendingPathComponent("\(entry.id.uuidString).json")
        var trimmed = entry
        trimmed.name = String(entry.name.prefix(MemoryEntry.nameCharLimit))
        trimmed.description = String(entry.description.prefix(MemoryEntry.descriptionCharLimit))
        trimmed.body = String(entry.body.prefix(MemoryEntry.bodyCharLimit))
        trimmed.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(trimmed) else {
            return .reject(reason: "Encoding failed")
        }
        try? data.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        return .allow
    }

    /// Delete a single entry by id. No-op when the file doesn't exist.
    static func delete(_ id: UUID) {
        guard let dir = directoryURL() else { return }
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Wipe every memory entry. Used by the global "Reset all data"
    /// path and the Settings → Memory "Clear all" button.
    static func clearAll() {
        guard let dir = directoryURL() else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json" {
            try? FileManager.default.removeItem(at: url)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    // MARK: - Disk paths

    private static func directoryURL() -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = support
            .appendingPathComponent("Orion", isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

import Foundation

/// Memory-specific AppSettings flags.
extension AppSettings {

    static let autoExtractMemoryKey = "autoExtractMemory"

    /// Run the post-turn memory extractor automatically?
    /// Default ON for new installs — the compounding-value case is the
    /// whole point of the memory layer. Sir can disable from
    /// Settings → Memory if the per-turn cost or noise becomes a bother.
    static var autoExtractMemoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoExtractMemoryKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoExtractMemoryKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoExtractMemoryKey)
        }
    }

    /// Wipe all memory-layer state. Called by the global "Reset all
    /// data" path so users can rehearse the first-launch flow without
    /// stray remembered facts haunting the new session.
    ///
    /// Conversations are deliberately not persisted — there's nothing
    /// to clear there. Only the durable fact memory + the auto-extract
    /// preference get reset.
    static func clearMemoryLayerState() {
        MemoryStore.clearAll()
        UserDefaults.standard.removeObject(forKey: autoExtractMemoryKey)
    }
}

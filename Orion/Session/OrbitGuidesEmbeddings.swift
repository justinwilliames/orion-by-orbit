import Foundation
import NaturalLanguage

/// On-device semantic re-rank over the Orbit guides corpus.
///
/// `OrbitGuidesCorpus` does a fast keyword-overlap pass to filter the
/// guides down to a candidate set. This file's job is to re-rank
/// that candidate set by sentence-embedding cosine similarity so the
/// returned guides are semantically relevant, not just lexically.
///
/// Why on-device with `NLEmbedding`:
///   - Apple ships a 512-dim sentence-embedding model in the OS
///     (`NLEmbedding.sentenceEmbedding(for: .english)`) — no model
///     bundling, no network, no third-party dependency.
///   - Full corpus vectorisation runs in milliseconds.
///   - Cosine over 512-dim vectors is trivially fast in Swift; no
///     vector index needed.
///
/// Lifecycle:
///   1. App launches.
///   2. First call to `precomputeIfNeeded()` (from `OrionApp`)
///      kicks off a background job that hashes the bundled corpus,
///      compares against the cached fingerprint on disk, and only
///      rebuilds when the corpus has actually changed.
///   3. Cache lives at
///      `~/Library/Application Support/Orion/orbit-guides-embeddings.json`
///      so subsequent launches skip recomputation entirely.
///   4. Per-query embeddings are tiny (one vector each) so we recompute
///      them on every call rather than maintaining a query cache.
///
/// Failure modes are silent — if `NLEmbedding` returns nil for a given
/// string, that guide just won't get re-ranked. The caller still has
/// the keyword score to fall back on.
enum OrbitGuidesEmbeddings {
    /// In-memory cache of {slug → 512-dim vector}. Populated either by
    /// loading the persisted file or by precomputing in-process.
    private static var vectors: [String: [Float]] = [:]
    private static let stateLock = NSLock()
    private static var isPrecomputing = false

    /// Stable fingerprint of the bundled corpus AND the OS-provided
    /// embedding model. Used to invalidate the cached embeddings when:
    ///   - the corpus refresh script writes a new JSON
    ///   - macOS ships a major update that may have swapped the
    ///     underlying NLEmbedding model (Apple has done this between
    ///     major OS versions before)
    ///
    /// Cheap derivation: count + first/last slug + total markdown
    /// byte length + OS major.minor — five signals that catch any
    /// real cause of cache staleness without forcing us to hash the
    /// full 856 KB JSON on every launch.
    private static func corpusFingerprint(_ entries: [OrbitGuidesCorpus.Entry]) -> String {
        guard let first = entries.first, let last = entries.last else { return "empty" }
        let totalBytes = entries.reduce(0) { $0 + $1.markdown.utf8.count }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osTag = "macos-\(os.majorVersion).\(os.minorVersion)"
        return "\(entries.count):\(first.slug):\(last.slug):\(totalBytes):\(osTag)"
    }

    /// Disk cache shape — version field reserved for forward-compat in
    /// case we change the embedding model or vector layout later.
    private struct CacheFile: Codable {
        let version: Int
        let corpusFingerprint: String
        let dimension: Int
        let vectors: [String: [Float]]
    }

    private static let cacheVersion = 1

    /// Async-fire-and-forget. Idempotent: safe to call on every app
    /// launch. Returns immediately on the calling thread; the actual
    /// vectorisation happens on a background queue.
    static func precomputeIfNeeded() {
        stateLock.lock()
        let alreadyRunning = isPrecomputing
        let alreadyLoaded = !vectors.isEmpty
        if !alreadyRunning && !alreadyLoaded {
            isPrecomputing = true
        }
        stateLock.unlock()

        guard !alreadyRunning, !alreadyLoaded else { return }

        DispatchQueue.global(qos: .utility).async {
            defer {
                stateLock.lock()
                isPrecomputing = false
                stateLock.unlock()
            }

            let entries = OrbitGuidesCorpus.entries
            guard !entries.isEmpty else { return }
            let fingerprint = corpusFingerprint(entries)

            // Try the disk cache first.
            if let cached = loadCache(), cached.corpusFingerprint == fingerprint, cached.version == cacheVersion {
                stateLock.lock()
                vectors = cached.vectors
                stateLock.unlock()
                return
            }

            // Cold path — compute every guide's vector. Apple's
            // sentence embedding model is loaded once per process via
            // the `NLEmbedding` shared instance.
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                // Embeddings unavailable on this OS — keyword retrieval
                // still works. No-op.
                return
            }

            var built: [String: [Float]] = [:]
            built.reserveCapacity(entries.count)
            for entry in entries {
                // Compose the embedding source: title + summary + a
                // leading slice of the body. Pure-body embedding loses
                // titular signal; pure-title is too narrow.
                let body = entry.markdown.prefix(1_500)
                let composite = "\(entry.title). \(entry.summary). \(body)"
                if let vec = embedding.vector(for: composite) {
                    built[entry.slug] = vec.map { Float($0) }
                }
            }

            stateLock.lock()
            vectors = built
            stateLock.unlock()

            saveCache(CacheFile(
                version: cacheVersion,
                corpusFingerprint: fingerprint,
                dimension: embedding.dimension,
                vectors: built
            ))
        }
    }

    /// Cosine similarity between the live query embedding and the
    /// cached vector for `slug`. Returns nil if embeddings aren't
    /// loaded yet, the slug isn't in the cache, or the query couldn't
    /// be vectorised. Callers must treat nil as "no signal" rather
    /// than "zero similarity".
    static func cosineSimilarity(query: String, slug: String) -> Double? {
        stateLock.lock()
        let snapshot = vectors
        stateLock.unlock()
        guard let target = snapshot[slug] else { return nil }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let queryVecD = embedding.vector(for: query) else {
            return nil
        }
        let queryVec = queryVecD.map { Float($0) }
        guard queryVec.count == target.count else { return nil }

        var dot: Float = 0
        var qNorm: Float = 0
        var tNorm: Float = 0
        for i in 0..<queryVec.count {
            dot += queryVec[i] * target[i]
            qNorm += queryVec[i] * queryVec[i]
            tNorm += target[i] * target[i]
        }
        let denom = (qNorm.squareRoot() * tNorm.squareRoot())
        guard denom > 0 else { return nil }
        return Double(dot / denom)
    }

    /// True once any vectors are loaded — keyword retrieval can use
    /// this to decide whether to apply the embedding re-rank.
    static var isReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !vectors.isEmpty
    }

    // MARK: - Disk cache

    private static func cacheURL() -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = support.appendingPathComponent("Orion", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("orbit-guides-embeddings.json")
    }

    private static func loadCache() -> CacheFile? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    private static func saveCache(_ file: CacheFile) {
        guard let url = cacheURL(),
              let data = try? JSONEncoder().encode(file) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

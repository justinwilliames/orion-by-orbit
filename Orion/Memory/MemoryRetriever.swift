import Foundation
import NaturalLanguage

/// Picks which memories to splice into the system prompt for a given
/// user message. Cosine-similarity over Apple's on-device sentence
/// embedding model (the same NLEmbedding instance OrbitGuidesEmbeddings
/// uses), with pinned entries always included regardless of score.
///
/// Selection rules:
///   1. Every pinned entry, always (capped at 5 to bound prompt size).
///   2. Top-K most similar non-pinned entries, with a minimum cosine
///      threshold so a query like "hi" doesn't pull random memories.
///   3. Total cap of `maxEntries` to keep the system prompt section
///      under ~2KB.
enum MemoryRetriever {

    /// Default budget — five memories is enough to ground an answer
    /// without dominating the system prompt. Higher values regress
    /// faster on cache hits.
    static let defaultMaxEntries = 5

    /// Cosine cut-off below which a non-pinned memory isn't worth
    /// including. Apple's sentence embedding routinely scores 0.3–0.4
    /// even for unrelated text; 0.45 catches genuinely related content.
    static let minimumCosineForNonPinned: Double = 0.45

    /// Returns the prompt-ready system-prompt block, or empty string
    /// when there's nothing relevant or no entries on disk yet. The
    /// caller splices this into `buildInstructions` alongside the
    /// business-context block.
    static func systemPromptSection(for query: String, maxEntries: Int = defaultMaxEntries) -> String {
        let selected = selected(for: query, maxEntries: maxEntries)
        guard !selected.isEmpty else { return "" }

        var lines: [String] = [
            "WHAT YOU REMEMBER ABOUT THE USER",
            "Durable facts you've accumulated from past conversations. Use them to skip context the user has already given you, choose examples that fit their world, and avoid asking questions whose answers are below. Don't quote them back at the user. Star (★) marks pinned entries the user explicitly cares about.",
            ""
        ]
        for entry in selected {
            lines.append(entry.promptLine())
        }
        return lines.joined(separator: "\n")
    }

    /// Underlying selection — exposed for tests and for the future
    /// case where we want to render the same "what I remembered" set
    /// in a debug pane.
    static func selected(for query: String, maxEntries: Int = defaultMaxEntries) -> [MemoryEntry] {
        let all = MemoryStore.all()
        guard !all.isEmpty else { return [] }

        // Pinned first — always included, in the order MemoryStore.all
        // already gave us (pinned-first, then by sortOrder, then recency).
        let pinned = all.filter(\.pinned)
        let unpinned = all.filter { !$0.pinned }

        // Vectorise the query once. If the model isn't available
        // (rare — Apple ships it on macOS 14+), skip the embedding
        // pass and fall back to recency-only ordering.
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let queryVector = embedding?.vector(for: query)

        var scoredUnpinned: [(MemoryEntry, Double)] = []
        if let queryVector {
            for entry in unpinned {
                guard let entryVector = embedding?.vector(for: entry.embeddableText) else { continue }
                let cosine = cosineSimilarity(queryVector, entryVector)
                if cosine >= minimumCosineForNonPinned {
                    scoredUnpinned.append((entry, cosine))
                }
            }
            scoredUnpinned.sort { $0.1 > $1.1 }
        } else {
            // Embedding unavailable — fall back to recency.
            scoredUnpinned = unpinned.map { ($0, 0) }
        }

        let pinnedSlice = Array(pinned.prefix(maxEntries))
        let remainingBudget = max(0, maxEntries - pinnedSlice.count)
        let unpinnedSlice = scoredUnpinned.prefix(remainingBudget).map(\.0)
        return pinnedSlice + unpinnedSlice
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var aNorm: Double = 0
        var bNorm: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            aNorm += a[i] * a[i]
            bNorm += b[i] * b[i]
        }
        let denom = aNorm.squareRoot() * bNorm.squareRoot()
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}

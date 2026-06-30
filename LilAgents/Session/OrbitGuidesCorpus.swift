import Foundation

/// In-app retrieval over the Orbit guides corpus.
///
/// At build time we bundle the full export from
/// `https://yourorbit.team/api/guides/export` as `orbit-guides.json`
/// (~850 KB, count from JSON × ~9 KB markdown each). On first access the
/// JSON is parsed once and cached for the process lifetime — the file
/// is small enough that holding it in memory is cheaper than re-decoding
/// per turn.
///
/// `relevantGuides(for:topK:)` does a lightweight keyword-overlap score
/// (no embeddings, no network, no extra deps) and returns the top-K
/// guides. The caller then injects truncated markdown excerpts into the
/// per-turn prompt so the model can ground its answer in actual guide
/// content rather than just citing slugs from a manifest.
///
/// The corpus is refreshed on demand by re-running
/// `Scripts/refresh-orbit-guides.sh` and committing the new JSON.
enum OrbitGuidesCorpus {
    struct Entry: Decodable {
        let slug: String
        let title: String
        let summary: String
        let category: String
        let canonicalUrl: String
        let primarySkill: String
        let markdown: String
        let targetQuery: String?
    }

    private struct Payload: Decodable {
        let count: Int
        let guides: [Entry]
    }

    /// Lazily-loaded entry list. Empty if the bundle is missing or the
    /// JSON is malformed — retrieval just returns nothing in that case
    /// rather than blowing up the whole prompt-build path.
    static let entries: [Entry] = loadFromBundle()

    /// Top-K guides ordered by descending relevance to `query`.
    ///
    /// Two-stage hybrid retrieval:
    ///   1. **Keyword pass** scores every guide by token overlap over
    ///      title, summary, slug, targetQuery, and a leading body
    ///      slice. Title hits weigh 5×, summary 3×, body 1×. Cheap,
    ///      runs over all guides in microseconds.
    ///   2. **Embedding re-rank** — when `OrbitGuidesEmbeddings` has
    ///      finished its background precompute, the top
    ///      `keywordCandidates` candidates are re-scored using cosine
    ///      similarity against Apple's sentence-embedding model. This
    ///      catches conceptual matches keyword overlap misses (e.g.
    ///      "users who keep cancelling" → `subscription-churn-saves`).
    ///
    /// On first launch (or a refreshed corpus) the embedding cache is
    /// still warming up, so the keyword score is what gets returned.
    /// Once warm, hybrid scoring kicks in transparently.
    static func relevantGuides(for query: String, topK: Int = 3) -> [Entry] {
        let tokens = tokenise(query)
        guard !tokens.isEmpty, !entries.isEmpty else { return [] }

        // Stage 1: keyword scoring across the whole corpus.
        let keywordScored: [(Entry, Int)] = entries.map { entry in
            let haystack = "\(entry.title)  \(entry.summary)  \(entry.slug)  \(entry.targetQuery ?? "")  \(entry.markdown.prefix(2_000))".lowercased()
            var score = 0
            for token in tokens {
                if haystack.contains(token) {
                    // Title hits are worth more — they signal direct
                    // topical match rather than incidental keyword overlap.
                    let titleHit = entry.title.lowercased().contains(token)
                    let summaryHit = entry.summary.lowercased().contains(token)
                    score += titleHit ? 5 : (summaryHit ? 3 : 1)
                }
            }
            return (entry, score)
        }

        // Decide whether to attempt embedding re-rank. If embeddings
        // aren't loaded yet, fall back to pure keyword retrieval.
        guard OrbitGuidesEmbeddings.isReady else {
            return keywordScored
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .prefix(topK)
                .map(\.0)
        }

        // Stage 2: take a wider candidate slice (4× topK or all
        // non-zero hits, whichever is smaller) so the embedding pass
        // has room to surface a semantically-strong result that didn't
        // win the keyword race. Always include guides with zero
        // keyword score iff the candidate pool is too small — protects
        // against pure-conceptual queries where no token overlaps.
        let keywordCandidates = max(topK * 4, 12)
        let nonZero = keywordScored.filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let candidatePool: [(Entry, Int)]
        if nonZero.count >= keywordCandidates {
            candidatePool = Array(nonZero.prefix(keywordCandidates))
        } else {
            // Pad with high-quality guides the keyword pass missed.
            // Embeddings will sort them out.
            let zeroTail = keywordScored.filter { $0.1 == 0 }.prefix(keywordCandidates - nonZero.count)
            candidatePool = nonZero + zeroTail.map { $0 }
        }

        // Combined score — keyword normalised to [0, 1] plus 2× cosine
        // weight so semantic match outweighs pure lexical match. The
        // 2× factor was picked by intuition; tune via real queries.
        let maxKeyword = max(1, candidatePool.map(\.1).max() ?? 1)
        let rescored: [(Entry, Double)] = candidatePool.map { (entry, kw) in
            let kwNorm = Double(kw) / Double(maxKeyword)
            let cosine = OrbitGuidesEmbeddings.cosineSimilarity(query: query, slug: entry.slug) ?? 0.0
            // Cosine for sentence-embedding models typically lives in
            // [0.4, 0.85] for related text — clamp the lower end so a
            // weak semantic match doesn't dominate a strong keyword hit.
            let cosineClamped = max(0, cosine - 0.3) * (1.0 / 0.7)
            return (entry, kwNorm + 2.0 * cosineClamped)
        }

        return rescored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map(\.0)
    }

    /// Render a compact prompt section the model can consume verbatim.
    /// Each guide is truncated to `excerptLimit` characters so 3 guides
    /// stay well under the 5–6 KB the per-turn prompt budget can spare.
    static func promptSection(for query: String, topK: Int = 3, excerptLimit: Int = 1_400) -> String {
        let hits = relevantGuides(for: query, topK: topK)
        guard !hits.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("RELEVANT ORBIT GUIDE EXCERPTS — use these to ground your answer. Quote sparingly; cite the slug in the Sources block. Don't paste the excerpt back at the user.")
        lines.append("")
        for hit in hits {
            lines.append("--- \(hit.slug) — \(hit.title)")
            lines.append("URL: \(hit.canonicalUrl)")
            lines.append("Summary: \(hit.summary)")
            lines.append("")
            lines.append(truncate(hit.markdown, to: excerptLimit))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Internals

    private static func loadFromBundle() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "orbit-guides", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.guides
        } catch {
            return []
        }
    }

    /// Cheap query tokeniser. Lowercases, splits on non-alphanumerics,
    /// strips short noise tokens and a small stop list. Not a real
    /// tokenizer — just enough to score keyword overlap honestly.
    private static func tokenise(_ raw: String) -> [String] {
        let lower = raw.lowercased()
        let chunks = lower.split { ch in
            !(ch.isLetter || ch.isNumber)
        }.map(String.init)

        let stop: Set<String> = [
            "the", "and", "for", "with", "what", "how", "why", "when",
            "where", "are", "is", "this", "that", "you", "your", "from",
            "have", "has", "been", "any", "some", "there", "about", "into",
            "out", "but", "can", "should", "would", "could", "will", "just",
            "really", "very", "much", "more", "less", "than", "then", "them",
            "they", "their", "ours", "our", "i", "me", "my", "we", "us",
        ]

        return chunks.compactMap { token in
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 3, !stop.contains(cleaned) else { return nil }
            return cleaned
        }
    }

    private static func truncate(_ markdown: String, to limit: Int) -> String {
        let normalised = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalised.count > limit else { return normalised }
        // Cut at a paragraph or sentence boundary near the limit, not
        // mid-word — keeps the excerpt readable for the model.
        let head = String(normalised.prefix(limit))
        if let cutoff = head.range(of: "\n\n", options: .backwards) {
            return String(head[..<cutoff.lowerBound]) + "\n\n[…guide continues at canonical URL…]"
        }
        if let cutoff = head.range(of: ". ", options: .backwards) {
            return String(head[..<cutoff.upperBound]) + " […guide continues at canonical URL…]"
        }
        return head + "…"
    }
}

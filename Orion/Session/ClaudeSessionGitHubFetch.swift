import Foundation

extension ClaudeSession {

    private static let archiveIndexURL = URL(string: "https://raw.githubusercontent.com/LennysNewsletter/lennys-newsletterpodcastdata/main/index.json")!
    private static let archiveFileBase = "https://raw.githubusercontent.com/LennysNewsletter/lennys-newsletterpodcastdata/main/"

    /// Two-step GitHub archive pre-fetch for the OpenAI path.
    /// Step 1: Fetch index.json, score entries by relevance to the query.
    /// Step 2: Fetch the top 1–2 matching files and inject their content.
    /// Emits live status via onToolUse/onToolResult. Calls completion on main thread.
    func prefetchGitHubArchiveContext(
        message: String,
        expert: ResponderExpert?,
        conversationKey: String,
        completion: @escaping (String) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onToolUse?("Searching archive", ["summary": "Fetching archive index…"])
            self.appendHistory(Message(role: .toolUse, text: "Searching archive: Fetching archive index…"), to: conversationKey)
        }

        Task {
            do {
                let (indexData, _) = try await URLSession.shared.data(from: Self.archiveIndexURL)
                guard let indexJSON = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any] else {
                    SessionDebugLogger.log("github-fetch", "index.json parse failed")
                    DispatchQueue.main.async { completion("") }
                    return
                }

                var entries: [[String: Any]] = []
                if let podcasts = indexJSON["podcasts"] as? [[String: Any]] { entries.append(contentsOf: podcasts) }
                if let newsletters = indexJSON["newsletters"] as? [[String: Any]] { entries.append(contentsOf: newsletters) }
                SessionDebugLogger.log("github-fetch", "index loaded. total entries=\(entries.count)")

                let query = buildGitHubSearchQuery(message: message, expert: expert)
                let top = scoreAndRankEntries(entries, query: query, limit: 2)
                SessionDebugLogger.log("github-fetch", "ranked entries. top=\(top.compactMap { $0["title"] as? String })")

                if top.isEmpty {
                    SessionDebugLogger.log("github-fetch", "no matching entries found")
                    DispatchQueue.main.async { [weak self] in
                        self?.onToolResult?("No strong archive matches for this query", false)
                        completion("")
                    }
                    return
                }

                let label = top.count == 1 ? "1 episode" : "\(top.count) episodes"
                DispatchQueue.main.async { [weak self] in
                    self?.onToolUse?("Searching archive", ["summary": "Reading \(label)…"])
                }

                var contextSections: [String] = []
                for entry in top {
                    guard let filename = entry["filename"] as? String,
                          let fileURL = URL(string: Self.archiveFileBase + filename) else { continue }
                    SessionDebugLogger.log("github-fetch", "fetching \(filename)")
                    if let (fileData, _) = try? await URLSession.shared.data(from: fileURL),
                       let fileText = String(data: fileData, encoding: .utf8) {
                        let title = entry["title"] as? String ?? filename
                        let date = entry["date"] as? String ?? ""
                        let truncated = String(fileText.prefix(6_000))
                        contextSections.append("## \(title) (\(date))\n\(truncated)")
                        SessionDebugLogger.log("github-fetch", "loaded \(filename) chars=\(truncated.count)")
                    }
                }

                let context = contextSections.joined(separator: "\n\n---\n\n")
                let resultSummary = "Loaded \(contextSections.count) archive source\(contextSections.count == 1 ? "" : "s")"
                SessionDebugLogger.log("github-fetch", resultSummary)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.onToolResult?(resultSummary, false)
                    self.appendHistory(Message(role: .toolResult, text: resultSummary), to: conversationKey)
                    completion(context)
                }

            } catch {
                SessionDebugLogger.log("github-fetch", "prefetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion("") }
            }
        }
    }

    private func buildGitHubSearchQuery(message: String, expert: ResponderExpert?) -> String {
        [expert?.name, message]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scoreAndRankEntries(_ entries: [[String: Any]], query: String, limit: Int) -> [[String: Any]] {
        let stopWords: Set<String> = ["the", "and", "for", "that", "with", "this", "are", "was", "were", "how", "what", "why", "when", "you", "your", "have", "does", "can", "about", "from", "write", "more", "detail", "answer", "tell", "give", "please", "also", "just", "say", "call"]
        let queryWords = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        guard !queryWords.isEmpty else { return [] }

        let scored: [(entry: [String: Any], score: Int)] = entries.compactMap { entry in
            let guestText = (entry["guest"] as? String ?? "").lowercased()
            let titleText = (entry["title"] as? String ?? "").lowercased()
            let descText = [entry["description"] as? String, entry["subtitle"] as? String]
                .compactMap { $0 }.joined(separator: " ").lowercased()

            let score = queryWords.reduce(0) { acc, word in
                if guestText.contains(word) { return acc + 3 }  // exact guest name match
                if titleText.contains(word) { return acc + 2 }  // title keyword match
                if descText.contains(word) { return acc + 1 }   // description match
                return acc
            }
            guard score > 0 else { return nil }
            return (entry, score)
        }

        let ranked = scored.sorted { $0.score > $1.score }

        // Require a minimum relevance score of 3 — anything lower means the query
        // is a generic follow-up (e.g. "write more detail") and the model should
        // rely on previous_response_id cache instead of a fresh but irrelevant fetch.
        guard let topScore = ranked.first?.score, topScore >= 3 else { return [] }

        return ranked.prefix(limit).map(\.entry)
    }
}

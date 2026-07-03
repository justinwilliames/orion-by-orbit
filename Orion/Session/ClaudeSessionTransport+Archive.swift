import Foundation

extension ClaudeSession {
    private static let githubArchiveRawBase = "https://raw.githubusercontent.com/LennysNewsletter/lennys-newsletterpodcastdata/main"

    func githubArchiveContext(for backend: Backend, expert: ResponderExpert?) -> String {
        let expertHint = expert.map { "\nFocus on content featuring \($0.name)." } ?? ""
        switch backend {
        case .claudeCodeCLI, .codexCLI:
            return """
            Use WebFetch to search Lenny's public archive on GitHub:\(expertHint)
            1. Fetch the index to discover what's available:
               \(Self.githubArchiveRawBase)/index.json
               (JSON with "podcasts" and "newsletters" arrays; each entry has: title, filename, date, guest, description, word_count)
            2. Fetch 1–3 of the most relevant files:
               \(Self.githubArchiveRawBase)/{filename}
               (e.g. "podcasts/ryan-hoover.md" or "newsletters/lenny-2024-01-15.md")
            3. Ground your answer in what you retrieved.
            Do not describe the fetching steps in your response.
            """
        case .openAIResponsesAPI:
            return """
            Lenny's public archive:\(expertHint)
            Index: \(Self.githubArchiveRawBase)/index.json
            Files: \(Self.githubArchiveRawBase)/{filename}
            Answer using your knowledge of Lenny Rachitsky's content. Cite specific episodes or newsletters when relevant.
            """
        }
    }

    func searchStarterArchive(message: String, expert: ResponderExpert?) -> (promptContext: String, experts: [ResponderExpert], summary: String, resultSummary: String) {
        let query = [expert?.name, message]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        SessionDebugLogger.log("starter-pack", "search query=\(query)")
        let matches = LocalArchive.shared.search(query: query, limit: 4)

        if matches.isEmpty {
            let promptContext = """
            The bundled starter archive did not contain a strong match for this query.
            Be transparent that the starter pack only includes 10 newsletters and 50 podcast transcripts.
            Suggest switching Settings to Official Lenny MCP for the full archive if needed.
            """
            return (
                promptContext,
                [],
                "Searching the bundled starter pack",
                "No strong matches found in the bundled starter pack"
            )
        }

        let contextLines = matches.enumerated().map { index, match in
            let subtitle = match.entry.subtitle ?? match.entry.description ?? ""
            let subtitleSuffix = subtitle.isEmpty ? "" : "\nSubtitle: \(subtitle)"
            return """
            \(index + 1). [\(match.entry.typeLabel.capitalized)] \(match.entry.title) (\(match.entry.date))
            File: \(match.entry.filename)\(subtitleSuffix)
            Excerpt: \(match.excerpt)
            """
        }
        let promptContext = contextLines.joined(separator: "\n\n")

        let experts = matches.compactMap { match -> ResponderExpert? in
            let name = match.entry.guest ?? speakerName(fromTitle: match.entry.title)
            guard let name, let avatarPath = avatarPath(for: name) else { return nil }
            return makeResponderExpert(
                name: name,
                avatarPath: avatarPath,
                archiveContext: "- \(match.entry.title) (\(match.entry.date)): \(match.excerpt)"
            )
        }

        let uniqueExperts = experts.reduce(into: [ResponderExpert]()) { partial, expert in
            if !partial.contains(where: { $0.name == expert.name }) {
                partial.append(expert)
            }
        }

        return (
            promptContext,
            Array(uniqueExperts.prefix(3)),
            "Searching the bundled starter pack",
            "Loaded \(matches.count) starter-pack match\(matches.count == 1 ? "" : "es")"
        )
    }

    func publishPendingExperts(fallbackText: String? = nil) {
        let experts = pendingExperts
        pendingExperts.removeAll()
        let assistantRequestedExperts = assistantExplicitlyRequestedExperts
        assistantExplicitlyRequestedExperts = false

        guard assistantRequestedExperts else {
            if let fallbackText, fallbackText.contains("\"answer_markdown\"") {
                SessionDebugLogger.log("experts", "skipping staged experts because assistant output was not parsed cleanly")
            } else {
                SessionDebugLogger.log("experts", "skipping staged experts because assistant did not explicitly request them")
            }
            return
        }

        guard !experts.isEmpty else {
            SessionDebugLogger.log("experts", "no staged experts to publish")
            return
        }

        let names = experts.map(\.name).joined(separator: ", ")
        SessionDebugLogger.log("experts", "publishing \(experts.count) expert candidate(s) after response completion: \(names)")
        onExpertsUpdated?(experts)
    }
}

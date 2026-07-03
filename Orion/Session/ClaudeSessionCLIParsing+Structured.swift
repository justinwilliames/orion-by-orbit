import Foundation

extension ClaudeSession {
    func structuredResponse(from json: [String: Any]) -> (segments: [AssistantSegment], suggestedExperts: [ResponderExpert], suggestExpertPrompt: Bool)? {
        var segments: [AssistantSegment] = []

        if let rawMessages = json["messages"] as? [[String: Any]] {
            for raw in rawMessages {
                guard let markdown = raw["markdown"] as? String,
                      let speakerName = (raw["speaker"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !speakerName.isEmpty else { continue }
                let kind = ((raw["kind"] as? String) ?? "").lowercased()
                let linkified = CitationLinkifier.linkify(markdown)
                if kind == "expert", let expert = expertSuggestion(named: speakerName) {
                    segments.append(AssistantSegment(speaker: speaker(for: expert), markdown: linkified, followUpExpert: expert))
                } else {
                    let speakerValue = normalize(speakerName) == normalize("Orion")
                        ? justinSpeaker()
                        : TranscriptSpeaker(name: speakerName, avatarPath: nil, kind: .system)
                    segments.append(AssistantSegment(speaker: speakerValue, markdown: linkified, followUpExpert: nil))
                }
            }
        }

        if segments.isEmpty, let answerMarkdown = json["answer_markdown"] as? String {
            segments = [AssistantSegment(speaker: justinSpeaker(), markdown: CitationLinkifier.linkify(answerMarkdown), followUpExpert: nil)]
        }

        guard !segments.isEmpty else { return nil }

        let explicitExperts = (json["suggested_experts"] as? [String] ?? []).compactMap { expertSuggestion(named: $0) }
        let impliedExperts = segments.compactMap(\.followUpExpert)
        let uniqueExperts = (explicitExperts + impliedExperts).reduce(into: [ResponderExpert]()) { partial, expert in
            if !partial.contains(where: { $0.name == expert.name }) {
                partial.append(expert)
            }
        }
        let suggestExpertPrompt = json["suggest_expert_prompt"] as? Bool ?? !uniqueExperts.isEmpty
        let suggestedExperts = Array(uniqueExperts.prefix(3))
        return (sanitizedOrchestrationSegments(segments, suggestedExperts: suggestedExperts), suggestedExperts, suggestExpertPrompt)
    }

    func sanitizedOrchestrationSegments(_ segments: [AssistantSegment], suggestedExperts: [ResponderExpert]) -> [AssistantSegment] {
        let knownExperts = (suggestedExperts + segments.compactMap(\.followUpExpert)).reduce(into: [ResponderExpert]()) { partial, expert in
            if !partial.contains(where: { $0.name == expert.name }) {
                partial.append(expert)
            }
        }

        guard !knownExperts.isEmpty else { return segments }

        return segments.map { segment in
            guard segment.speaker.kind == .orion else { return segment }
            let sanitized = sanitizedOrchestrationMarkdown(segment.markdown, experts: knownExperts)
            guard sanitized != segment.markdown else { return segment }
            return AssistantSegment(speaker: segment.speaker, markdown: sanitized, followUpExpert: segment.followUpExpert)
        }
    }

    private func sanitizedOrchestrationMarkdown(_ markdown: String, experts: [ResponderExpert]) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return markdown }

        let cleaned = trimmed
        let lowered = cleaned.lowercased()
        let mentionedExperts = experts.filter {
            cleaned.localizedCaseInsensitiveContains("@\($0.name)") ||
            cleaned.localizedCaseInsensitiveContains($0.name)
        }
        let shouldCondense = cleaned.contains("@")
            || lowered.contains("bring in")
            || lowered.contains("join")
            || lowered.contains("thoughts on this")
            || lowered.contains("concrete")
            || (mentionedExperts.count >= 2 && cleaned.count > 120)

        guard shouldCondense, !mentionedExperts.isEmpty else { return cleaned }
        return orchestrationSummary(for: mentionedExperts.map(\.name))
    }

    private func orchestrationSummary(for names: [String]) -> String {
        let uniqueNames = names.reduce(into: [String]()) { partial, name in
            if !partial.contains(name) {
                partial.append(name)
            }
        }

        switch uniqueNames.count {
        case 0:
            return "Bringing in a specialist perspective."
        case 1:
            return "Bringing in @\(uniqueNames[0]) for a practical perspective."
        case 2:
            return "Bringing in @\(uniqueNames[0]) and @\(uniqueNames[1]) for practical perspectives."
        default:
            return "Bringing in @\(uniqueNames[0]), @\(uniqueNames[1]), and @\(uniqueNames[2]) for practical perspectives."
        }
    }

    func expertSuggestion(named rawName: String) -> ResponderExpert? {
        // Orion is single-persona: the expert catalog (avatars, canonical
        // names, GuestTitles) was removed with the archive subsystem, so
        // there are no experts to suggest. Always nil — the structured-JSON
        // parser then treats every segment as an Orion/system message.
        _ = rawName
        return nil
    }

    func decodeStructuredAssistantJSONObject(from outputText: String) -> [String: Any]? {
        StructuredJSONParser.decodeJSONObject(from: outputText)
    }

    func extractStructuredJSONCandidate(from outputText: String) -> String? {
        StructuredJSONParser.extractCandidate(from: outputText)
    }

    /// Last-ditch fallback exposed to `prepareAssistantResponse` so a
    /// JSON-envelope failure shows the prose body instead of dumping
    /// raw JSON to the user. Wraps the pure-logic implementation.
    func extractFallbackMessageMarkdown(from outputText: String) -> String? {
        StructuredJSONParser.extractMessageMarkdownFallback(from: outputText)
    }
}

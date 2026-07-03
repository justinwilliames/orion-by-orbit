import Foundation

extension ClaudeSession {
    func finishCLIResponse(_ outputText: String, conversationKey: String) {
        let response = prepareAssistantResponse(outputText)
        // Diagnostic: when the structured-JSON parser fails, the raw
        // JSON envelope leaks to the user (Sir's 2026-04-30 screenshot
        // bug). Log when the markdown fallback path was used so
        // Console.app filtered to "[Orion]" reveals which inputs
        // bypass strict parsing — locks in evidence for follow-up
        // regression tests.
        if response.parsedFromStructuredJSON == false {
            let preview = String(outputText.prefix(400))
            NSLog("[Orion] structured-JSON parse FAILED — falling back to markdown extraction. inputPrefix=\(preview)")
        }
        publishPendingExperts(fallbackText: response.displayText)
        SessionDebugLogger.logMultiline("assistant", header: "finishCLIResponse()", body: response.displayText)
        let composeSummary = "Composing the final answer"
        onToolUse?("Writing", ["summary": composeSummary])
        appendHistory(Message(role: .toolUse, text: "Writing: \(composeSummary)"), to: conversationKey)
        response.messages.forEach { appendHistory($0, to: conversationKey) }
        onText?(response.displayText)
        finishTurn()
    }

    func prepareAssistantResponse(_ outputText: String) -> (messages: [Message], displayText: String, parsedFromStructuredJSON: Bool) {
        if let payload = parseStructuredAssistantResponse(from: outputText) {
            let segments: [AssistantSegment]
            if let focusedExpert {
                let matchingSegments = payload.segments.filter {
                    $0.speaker.kind == .expert && normalize($0.speaker.name) == normalize(focusedExpert.name)
                }
                if !matchingSegments.isEmpty {
                    segments = matchingSegments
                } else if let fallbackMarkdown = payload.segments
                    .map(\.markdown)
                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .last(where: { !$0.isEmpty }) {
                    segments = [AssistantSegment(speaker: speaker(for: focusedExpert), markdown: fallbackMarkdown, followUpExpert: focusedExpert)]
                } else {
                    segments = []
                }
            } else {
                segments = payload.segments
            }

            assistantExplicitlyRequestedExperts = focusedExpert == nil && payload.suggestExpertPrompt
            pendingExperts = focusedExpert == nil ? payload.suggestedExperts : []

            if payload.suggestExpertPrompt {
                let names = pendingExperts.map(\.name).joined(separator: ", ")
                SessionDebugLogger.log("experts", "parsed \(pendingExperts.count) JSON expert candidate(s) from assistant output: \(names)")
            } else {
                SessionDebugLogger.log("experts", "assistant explicitly declined expert suggestions")
            }

            let displayText = segments.map(\.markdown).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return (assistantMessages(from: segments), displayText, true)
        }

        // Last-ditch markdown extraction. When the JSON envelope is
        // broken — unescaped quotes inside markdown, mid-stream
        // truncation, prose mixed with JSON — we'd previously dump
        // the entire raw output to the user as the fallback message.
        // That's the bug Sir caught in his 2026-04-30 screenshot.
        // Now: regex out the first `markdown` field's value and use
        // that as the prose body. Better degraded UX than raw JSON.
        if let extracted = extractFallbackMessageMarkdown(from: outputText)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extracted.isEmpty {
            let linkified = CitationLinkifier.linkify(extracted)
            let fallbackMessage = Message(role: .assistant, text: linkified, speaker: justinSpeaker(), followUpExpert: nil)
            return ([fallbackMessage], linkified, false)
        }

        let structuredNames = structuredExpertSuggestionNames(from: outputText)
        if !structuredNames.isEmpty {
            let structuredExperts = structuredNames.compactMap { name -> ResponderExpert? in
                guard let avatarPath = avatarPath(for: name) else { return nil }
                let context = "Explicitly suggested by the assistant in the latest answer."
                return makeResponderExpert(name: name, avatarPath: avatarPath, archiveContext: context)
            }

            assistantExplicitlyRequestedExperts = !structuredExperts.isEmpty
            pendingExperts = Array(structuredExperts.prefix(3))
            let names = pendingExperts.map(\.name).joined(separator: ", ")
            SessionDebugLogger.log("experts", "parsed \(pendingExperts.count) structured expert candidate(s) from assistant output: \(names)")
        }

        let cleaned = cleanedAssistantText(outputText)
        let linkified = CitationLinkifier.linkify(cleaned)
        let fallbackMessage = Message(role: .assistant, text: linkified, speaker: justinSpeaker(), followUpExpert: nil)
        return ([fallbackMessage], linkified, false)
    }

    func parseStructuredAssistantResponse(from outputText: String) -> (segments: [AssistantSegment], suggestedExperts: [ResponderExpert], suggestExpertPrompt: Bool)? {
        if let json = decodeStructuredAssistantJSONObject(from: outputText) {
            if let payload = structuredResponse(from: json) {
                let names = payload.suggestedExperts.map(\.name).joined(separator: ", ")
                SessionDebugLogger.log("assistant", "parsed structured JSON assistant payload. suggestedExperts=\(names) prompt=\(payload.suggestExpertPrompt)")
                return payload
            }
        }

        guard let answerMarkdown = extractStructuredJSONStringValue(forKey: "answer_markdown", from: outputText) else { return nil }
        let suggestedExperts = extractStructuredStringArray(forKey: "suggested_experts", from: outputText)
            .compactMap { expertSuggestion(named: $0) }
        let suggestExpertPrompt = extractStructuredBoolean(forKey: "suggest_expert_prompt", from: outputText) ?? !suggestedExperts.isEmpty
        let segments = sanitizedOrchestrationSegments(
            [AssistantSegment(speaker: justinSpeaker(), markdown: CitationLinkifier.linkify(answerMarkdown), followUpExpert: nil)],
            suggestedExperts: Array(suggestedExperts.prefix(3))
        )
        return (segments, Array(suggestedExperts.prefix(3)), suggestExpertPrompt)
    }
}

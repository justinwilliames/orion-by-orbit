import AppKit
import Foundation

extension ClaudeSession {
    /// Pull the assistant text out of an OpenAI Responses `output` array.
    /// Relocated from the deleted expert-resolution file; it is a general
    /// output-text extractor, not expert-specific.
    func extractMessageText(from outputItems: [[String: Any]]) -> String? {
        for item in outputItems where item["type"] as? String == "message" {
            let content = item["content"] as? [[String: Any]] ?? []
            let texts = content.compactMap { block -> String? in
                guard block["type"] as? String == "output_text" else { return nil }
                return block["text"] as? String
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        return nil
    }

    func callOpenAI(message: String, attachments: [SessionAttachment], apiKey: String, expert: ResponderExpert?, conversationKey: String, mcpToken: String?, archiveContext: String?) {
        let prompt = buildUserPrompt(message: message, attachments: attachments, expert: expert, archiveContext: archiveContext)
        let input: [[String: Any]] = [[
            "role": "user",
            "content": buildInputContent(prompt: prompt, attachments: attachments)
        ]]

        let instructions = buildInstructions(for: expert, expectMCP: mcpToken != nil)
        var payload: [String: Any] = [
            "model": selectedOpenAIModel(),
            "instructions": instructions,
            "input": input,
            "stream": true
        ]

        if let mcpToken {
            payload["tools"] = [[
                "type": "mcp",
                "server_label": Constants.lennyMCPServerLabel,
                "server_description": "Lenny Rachitsky's archive of newsletter posts and podcast transcripts about startups, product, growth, pricing, leadership, career, and AI product work.",
                "server_url": Constants.lennyMCPURL,
                "headers": [
                    "Authorization": "Bearer \(mcpToken)"
                ],
                "require_approval": "never",
                "allowed_tools": Constants.lennyAllowedTools
            ]]
        }

        if let previousResponseID = conversations[conversationKey]?.previousResponseID {
            payload["previous_response_id"] = previousResponseID
        }

        if let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let payloadText = String(data: payloadData, encoding: .utf8) {
            SessionDebugLogger.logMultiline(
                "openai",
                header: "dispatching OpenAI Responses API (streaming). conversationKey=\(conversationKey) expert=\(expert?.name ?? "none") mcpInjected=\(mcpToken != nil)",
                body: payloadText
            )
        }

        let modelLabel = selectedOpenAIModelLabel()
        let planningSummary = mcpToken == nil
            ? "Calling \(modelLabel) via OpenAI"
            : "Calling \(modelLabel) via OpenAI with Lenny MCP"
        onToolUse?("Planning", ["summary": planningSummary])
        appendHistory(Message(role: .toolUse, text: "Planning: \(planningSummary)"), to: conversationKey)

        var request = URLRequest(url: Constants.openAIEndpoint, timeoutInterval: Constants.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            failTurn("Couldn't encode the OpenAI request.", conversationKey: conversationKey)
            return
        }

        let streamTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            do {
                let (asyncBytes, _) = try await URLSession.shared.bytes(for: request)
                var hasStartedWriting = false
                var hasSignaledThinking = false

                for try await line in asyncBytes.lines {
                    if Task.isCancelled { return }
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))
                    guard jsonStr != "[DONE]",
                          let data = jsonStr.data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let eventType = event["type"] as? String else { continue }

                    // First event of any kind — connection is live, show thinking status
                    if !hasSignaledThinking {
                        hasSignaledThinking = true
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isCancellingTurn else { return }
                            self.onToolUse?("Thinking", ["summary": "Thinking through it…"])
                        }
                    }

                    switch eventType {

                    case "response.output_text.delta":
                        let delta = (event["delta"] as? String)
                            ?? (event["text"] as? String)
                            ?? ""
                        if !hasStartedWriting {
                            hasStartedWriting = true
                            DispatchQueue.main.async { [weak self] in
                                guard let self, !self.isCancellingTurn else { return }
                                self.onToolUse?("Writing", ["summary": "Writing the answer…"])
                            }
                        }
                        if !delta.isEmpty {
                            DispatchQueue.main.async { [weak self] in
                                guard let self, !self.isCancellingTurn else { return }
                                self.onTextDelta?(delta)
                            }
                        }

                    case "response.completed":
                        guard let responseObj = event["response"] as? [String: Any] else { continue }
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isCancellingTurn else { return }
                            self.currentStreamingTask = nil
                            self.handleOpenAICompletedResponse(responseObj, conversationKey: conversationKey)
                        }
                        return

                    case "error":
                        let message = event["message"] as? String ?? "Unknown streaming error"
                        SessionDebugLogger.log("openai", "stream error event: \(message)")
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isCancellingTurn else { return }
                            self.currentStreamingTask = nil
                            self.failTurn("OpenAI error: \(message)", conversationKey: conversationKey)
                        }
                        return

                    default:
                        break
                    }
                }

                // Stream ended without response.completed
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isCancellingTurn else { return }
                    self.currentStreamingTask = nil
                    self.failTurn("OpenAI stream ended unexpectedly.", conversationKey: conversationKey)
                }

            } catch {
                if !Task.isCancelled {
                    let desc = error.localizedDescription
                    SessionDebugLogger.log("openai", "streaming request failed: \(desc)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.isCancellingTurn else { return }
                        self.currentStreamingTask = nil
                        self.failTurn("OpenAI request failed: \(desc)", conversationKey: conversationKey)
                    }
                }
            }
        }
        currentStreamingTask = streamTask
    }

    // Handles the completed response object (from response.completed event).
    // Skips re-emitting MCP tool events since those already fired live during streaming.
    func handleOpenAICompletedResponse(_ json: [String: Any], conversationKey: String) {
        SessionDebugLogger.log("openai", "handleOpenAICompletedResponse()")

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            if let authError = normalizedLennyMCPAuthError(from: message) {
                failTurn(authError, conversationKey: conversationKey)
            } else {
                failTurn("OpenAI error: \(message)", conversationKey: conversationKey)
            }
            return
        }

        if let responseID = json["id"] as? String {
            var state = conversations[conversationKey] ?? ConversationState()
            state.previousResponseID = responseID
            conversations[conversationKey] = state
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let jsonText = String(data: jsonData, encoding: .utf8) {
            SessionDebugLogger.logMultiline("openai", header: "completed response object", body: jsonText)
        }

        let outputText = (json["output_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? extractMessageText(from: json["output"] as? [[String: Any]] ?? [])

        guard let outputText, !outputText.isEmpty else {
            failTurn("The model returned no final answer.", conversationKey: conversationKey)
            return
        }

        let response = prepareAssistantResponse(outputText)
        publishPendingExperts(fallbackText: response.displayText)
        SessionDebugLogger.logMultiline("assistant", header: "final assistant response", body: response.displayText)
        let composeSummary = "Composing the final answer"
        onToolUse?("Writing", ["summary": composeSummary])
        appendHistory(Message(role: .toolUse, text: "Writing: \(composeSummary)"), to: conversationKey)
        response.messages.forEach { appendHistory($0, to: conversationKey) }
        onText?(response.displayText)
        finishTurn()
    }
}

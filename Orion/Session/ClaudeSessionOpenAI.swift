import AppKit
import Foundation

extension ClaudeSession {
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
                var mcpExperts: [ResponderExpert] = []
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

                    case "response.output_item.added":
                        // Fire a "Searching..." status when an MCP call item starts
                        if let item = event["item"] as? [String: Any],
                           item["type"] as? String == "mcp_call",
                           let name = item["name"] as? String {
                            let display = self.processDisplay(for: name, arguments: [:])
                            DispatchQueue.main.async { [weak self] in
                                guard let self, !self.isCancellingTurn else { return }
                                self.onToolUse?(display.title, ["summary": display.summary])
                            }
                        }

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

                    case "response.mcp_call.completed":
                        let name = event["name"] as? String ?? "tool"
                        let rawArgs = event["arguments"]
                        let arguments: [String: Any]
                        if let argsDict = rawArgs as? [String: Any] {
                            arguments = argsDict
                        } else if let argsStr = rawArgs as? String,
                                  let d = argsStr.data(using: .utf8),
                                  let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                            arguments = parsed
                        } else {
                            arguments = [:]
                        }
                        let output = event["output"]
                        let experts = self.expertsFromMCPPayloads(arguments: arguments, output: output)
                        mcpExperts.append(contentsOf: experts.filter { e in !mcpExperts.contains(where: { $0.name == e.name }) })
                        let resultSummary = self.processResultDisplay(for: name, arguments: arguments, output: output)
                        let display = self.processDisplay(for: name, arguments: arguments)
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isCancellingTurn else { return }
                            self.onToolUse?(display.title, ["summary": display.summary, "experts": experts])
                            self.onToolResult?(resultSummary, false)
                        }

                    case "response.completed":
                        guard let responseObj = event["response"] as? [String: Any] else { continue }
                        let capturedExperts = mcpExperts
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isCancellingTurn else { return }
                            self.currentStreamingTask = nil
                            self.pendingExperts = capturedExperts
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

    func handleOpenAIResponse(_ json: [String: Any], conversationKey: String) {
        SessionDebugLogger.log("openai", "handleOpenAIResponse() outputItems=\((json["output"] as? [[String: Any]] ?? []).count)")
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            SessionDebugLogger.log("openai", "model returned error: \(message)")
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

        let outputItems = json["output"] as? [[String: Any]] ?? []
        var experts: [ResponderExpert] = []

        for item in outputItems {
            guard let type = item["type"] as? String else { continue }
            switch type {
            case "mcp_list_tools":
                let tools = item["tools"] as? [[String: Any]] ?? []
                let count = tools.count
                SessionDebugLogger.log("mcp", "mcp_list_tools returned \(count) tool(s)")
                let summary = "Connected to archive, \(count) tools ready"
                onToolResult?(summary, false)
                appendHistory(Message(role: .toolResult, text: summary), to: conversationKey)

            case "mcp_call":
                let name = item["name"] as? String ?? "mcp_call"
                let arguments = item["arguments"] as? [String: Any] ?? [:]
                let output = item["output"]
                SessionDebugLogger.logMultiline("mcp", header: "mcp_call \(name)", body: "arguments=\(arguments)\noutput=\(String(describing: item["output"]))")
                let extractedExperts = expertsFromMCPPayloads(arguments: arguments, output: output)
                let processStep = processDisplay(for: name, arguments: arguments)
                onToolUse?(processStep.title, ["summary": processStep.summary, "experts": extractedExperts])
                appendHistory(Message(role: .toolUse, text: "\(processStep.title): \(processStep.summary)"), to: conversationKey)

                for expert in extractedExperts where !experts.contains(expert) {
                    experts.append(expert)
                }

                let resultSummary = processResultDisplay(for: name, arguments: arguments, output: output)
                onToolResult?(resultSummary, false)
                appendHistory(Message(role: .toolResult, text: resultSummary), to: conversationKey)

            case "message":
                continue

            default:
                continue
            }
        }

        pendingExperts = experts
        SessionDebugLogger.log("experts", "staged \(experts.count) MCP-derived expert candidate(s) until response completion")

        let outputText = (json["output_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let outputText, !outputText.isEmpty {
            let response = prepareAssistantResponse(outputText)
            publishPendingExperts(fallbackText: response.displayText)
            SessionDebugLogger.logMultiline("assistant", header: "final assistant response", body: response.displayText)
            let composeSummary = "Composing the final answer"
            onToolUse?("Writing", ["summary": composeSummary])
            appendHistory(Message(role: .toolUse, text: "Writing: \(composeSummary)"), to: conversationKey)
            response.messages.forEach { appendHistory($0, to: conversationKey) }
            onText?(response.displayText)
            finishTurn()
            return
        }

        if let messageText = extractMessageText(from: outputItems), !messageText.isEmpty {
            let response = prepareAssistantResponse(messageText)
            publishPendingExperts(fallbackText: response.displayText)
            SessionDebugLogger.logMultiline("assistant", header: "final assistant message response", body: response.displayText)
            let composeSummary = "Composing the final answer"
            onToolUse?("Writing", ["summary": composeSummary])
            appendHistory(Message(role: .toolUse, text: "Writing: \(composeSummary)"), to: conversationKey)
            response.messages.forEach { appendHistory($0, to: conversationKey) }
            onText?(response.displayText)
            finishTurn()
            return
        }

        failTurn("The model returned no final answer.", conversationKey: conversationKey)
    }
}

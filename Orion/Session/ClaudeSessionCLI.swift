import Foundation

extension ClaudeSession {
    func callClaudeCodeCLI(executablePath: String, message: String, attachments: [SessionAttachment], environment: [String: String], expert: ResponderExpert?, conversationKey: String, archiveContext: String?) {
        let modelLabel = selectedClaudeModelLabel()
        let planningSummary = "Calling \(modelLabel) in Claude Code"
        onToolUse?("Planning", ["summary": planningSummary])
        appendHistory(Message(role: .toolUse, text: "Planning: \(planningSummary)"), to: conversationKey)

        let prompt = buildConversationPrompt(message: message, attachments: attachments, expert: expert, conversationKey: conversationKey, archiveContext: archiveContext, expectMCP: false)

        var args = [
            "-p",
            prompt,
            "--output-format",
            "stream-json",
            "--verbose",
            "--permission-mode",
            "dontAsk"
        ]

        if let model = selectedClaudeModel() {
            args.append(contentsOf: ["--model", model])
        }

        args.append(contentsOf: ["--allowedTools", "WebFetch"])

        if environment["ANTHROPIC_API_KEY"] != nil {
            args.append("--bare")
        }

        SessionDebugLogger.logMultiline(
            "claude-cli",
            header: "dispatching Claude Code CLI. executable=\(executablePath) args=\(args)",
            body: prompt
        )

        var streamedAssistantText = ""

        runProcess(
            executablePath: executablePath,
            arguments: args,
            environment: environment,
            workingDirectory: preferredWorkingDirectoryURL(),
            onLineReceived: { [weak self] line in
                guard let self, !self.isCancellingTurn else { return }
                SessionDebugLogger.trace("claude-transport", line)
                if self.handleApprovalPromptLine(line) {
                    return
                }

                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let assistantText = self.claudeCLIStreamText(from: json),
                       !assistantText.isEmpty,
                       assistantText != streamedAssistantText {
                        streamedAssistantText = assistantText
                        self.onText?(assistantText)
                    }

                    if let event = self.claudeCLIStreamEvent(from: json) {
                        self.onToolUse?(event.title, ["summary": event.summary])
                    }
                } else if !line.hasPrefix("{") && !line.hasPrefix("}") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let summary = String(trimmed.prefix(80))
                    self.onToolUse?("Calling Model", ["summary": summary])
                }
            }
        ) { [weak self] status, stdout, stderr in
            guard let self else { return }

            if self.isCancellingTurn {
                self.isCancellingTurn = false
                self.pendingExperts.removeAll()
                return
            }

            SessionDebugLogger.logMultiline(
                "claude-cli",
                header: "Claude Code CLI finished. exitCode=\(status)",
                body: "stdout:\n\(stdout)\n\nstderr:\n\(stderr)"
            )
            self.logClaudeCLIResultMetadata(from: stdout)

            let outputText = self.extractClaudeCLIResult(from: stdout)
            if status == 0, let outputText, !outputText.isEmpty {
                self.finishCLIResponse(outputText, conversationKey: conversationKey)
                return
            }

            let errorText = self.normalizeCLIError(stdout: stdout, stderr: stderr, fallback: "Claude Code CLI could not complete the request.")
            self.failTurn(errorText, conversationKey: conversationKey)
        }
    }

    func callCodexCLI(executablePath: String, message: String, attachments: [SessionAttachment], environment: [String: String], expert: ResponderExpert?, conversationKey: String, archiveContext: String?) {
        let modelLabel = selectedCodexModelLabel()
        let planningSummary = "Calling \(modelLabel) in Codex"
        onToolUse?("Planning", ["summary": planningSummary])
        appendHistory(Message(role: .toolUse, text: "Planning: \(planningSummary)"), to: conversationKey)

        let prompt = buildConversationPrompt(message: message, attachments: attachments, expert: expert, conversationKey: conversationKey, archiveContext: archiveContext, expectMCP: false)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("orion-codex-last-message-\(UUID().uuidString).md")
        let runtimeEnvironment = environment

        var args = [
            "-a",
            "never",
            "exec",
            "--json",
            "--skip-git-repo-check",
            "-s",
            "read-only",
            "-o",
            outputURL.path
        ]

        if let model = selectedCodexModel() {
            args.append(contentsOf: ["-m", model])
        }

        args.append(prompt)

        for attachment in attachments where attachment.kind == .image {
            args.insert(contentsOf: ["-i", attachment.url.path], at: args.count - 1)
        }

        SessionDebugLogger.logMultiline(
            "codex-cli",
            header: "dispatching Codex CLI. executable=\(executablePath) args=\(args)",
            body: prompt
        )

        runProcess(
            executablePath: executablePath,
            arguments: args,
            environment: runtimeEnvironment,
            workingDirectory: preferredWorkingDirectoryURL(),
            wantsInteractiveInput: false,
            allocatePseudoTerminal: false,
            onLineReceived: { [weak self] line in
                guard let self, !self.isCancellingTurn else { return }
                SessionDebugLogger.trace("codex-transport", line)
                if self.handleApprovalPromptLine(line) {
                    return
                }

                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let event = self.codexCLIStreamEvent(from: json) {
                    self.onToolUse?(event.title, ["summary": event.summary])
                    return
                }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if self.shouldIgnoreCodexTransportLine(trimmed) {
                    return
                }

                let summary = String(trimmed.prefix(80))
                self.onToolUse?("Calling Model", ["summary": summary])
            }
        ) { [weak self] status, stdout, stderr in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: outputURL) }

            if self.isCancellingTurn {
                self.isCancellingTurn = false
                self.pendingExperts.removeAll()
                return
            }

            SessionDebugLogger.logMultiline(
                "codex-cli",
                header: "Codex CLI finished. exitCode=\(status) outputFile=\(outputURL.path)",
                body: "stdout:\n\(stdout)\n\nstderr:\n\(stderr)"
            )

            let outputText = (try? String(contentsOf: outputURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let outputText {
                SessionDebugLogger.logMultiline("codex-cli", header: "Codex CLI output file contents", body: outputText)
            }

            if status == 0, let outputText, !outputText.isEmpty {
                self.finishCLIResponse(outputText, conversationKey: conversationKey)
                return
            }

            if status == 0,
               let streamedOutput = self.extractCodexCLIResult(from: stdout),
               !streamedOutput.isEmpty {
                self.finishCLIResponse(streamedOutput, conversationKey: conversationKey)
                return
            }

            let errorText = self.normalizeCLIError(stdout: stdout, stderr: stderr, fallback: "Codex CLI could not complete the request.")
            self.failTurn(errorText, conversationKey: conversationKey)
        }
    }

}

import Foundation

extension ClaudeSession {
    func callClaudeCodeCLI(executablePath: String, message: String, attachments: [SessionAttachment], environment: [String: String], expert: ResponderExpert?, conversationKey: String, archiveContext: String?, officialMCPToken: String?, useOfficialMCP: Bool) {
        let modelLabel = selectedClaudeModelLabel()
        let planningSummary = useOfficialMCP
            ? "Calling \(modelLabel) in Claude Code with Lenny MCP"
            : "Calling \(modelLabel) in Claude Code"
        onToolUse?("Planning", ["summary": planningSummary])
        appendHistory(Message(role: .toolUse, text: "Planning: \(planningSummary)"), to: conversationKey)

        let prompt = buildConversationPrompt(message: message, attachments: attachments, expert: expert, conversationKey: conversationKey, archiveContext: archiveContext, expectMCP: useOfficialMCP)
        var configURL: URL?

        if useOfficialMCP, let token = officialMCPToken {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("lenny-claude-mcp-\(UUID().uuidString).json")
            let config: [String: Any] = [
                "mcpServers": [
                    Constants.lennyMCPServerLabel: [
                        "type": "http",
                        "url": Constants.lennyMCPURL,
                        "headers": [
                            "Authorization": "Bearer \(token)"
                        ]
                    ]
                ]
            ]

            do {
                let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
                try data.write(to: url, options: [.atomic])
                configURL = url
            } catch {
                failTurn("Couldn’t prepare the Claude Code MCP config.", conversationKey: conversationKey)
                return
            }
        }

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

        if useOfficialMCP {
            args.append(contentsOf: ["--allowedTools", "mcp__\(Constants.lennyMCPServerLabel)__*"])
            if let configURL {
                args.append(contentsOf: ["--mcp-config", configURL.path, "--strict-mcp-config"])
            }
        } else {
            args.append(contentsOf: ["--allowedTools", "WebFetch"])
        }

        if environment["ANTHROPIC_API_KEY"] != nil {
            args.append("--bare")
        }

        SessionDebugLogger.logMultiline(
            "claude-cli",
            header: "dispatching Claude Code CLI. executable=\(executablePath) useOfficialMCP=\(useOfficialMCP) configURL=\(configURL?.path ?? "none") args=\(args)",
            body: prompt
        )

        // Tracks whether the archive MCP server actually registered tools in this session.
        // Set from the init event so the completion handler can detect a missing server
        // without relying on response-text pattern matching.
        var lennyMCPFoundInInit = false
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

                // Detect the init event and check if the archive MCP server loaded.
                if useOfficialMCP, !lennyMCPFoundInInit,
                   let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["type"] as? String) == "system",
                   (json["subtype"] as? String) == "init",
                   let tools = json["tools"] as? [String] {
                    lennyMCPFoundInInit = tools.contains { $0.hasPrefix("mcp__\(Constants.lennyMCPServerLabel)__") }
                    SessionDebugLogger.log(
                        "claude-cli",
                        lennyMCPFoundInInit
                            ? "init event: mcp__lennysdata__* tools present"
                            : "init event: no mcp__lennysdata__* tools — MCP server not loaded"
                    )
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
                        let experts = self.expertsFromTransport(
                            payload: json,
                            textCandidates: [event.summary, line]
                        )
                        self.onToolUse?(event.title, ["summary": event.summary, "experts": experts])
                    }
                } else if !line.hasPrefix("{") && !line.hasPrefix("}") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let summary = String(trimmed.prefix(80))
                    let experts = self.expertsFromTransport(
                        payload: ["message": trimmed],
                        textCandidates: [trimmed, summary]
                    )
                    self.onToolUse?("Calling Model", ["summary": summary, "experts": experts])
                }
            }
        ) { [weak self] status, stdout, stderr in
            guard let self else { return }
            if let configURL {
                try? FileManager.default.removeItem(at: configURL)
            }

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
                // If the init event showed no Lenny MCP tools, the server never
                // loaded — treat the entire response as an MCP connection failure.
                if useOfficialMCP, !lennyMCPFoundInInit {
                    SessionDebugLogger.log("claude-cli", "MCP server absent from init — failing turn and firing onMCPAuthFailure")
                    DispatchQueue.main.async {
                        self.failTurn(
                            "The archive isn't connected — your auth token may have expired or needs to be set up.",
                            conversationKey: conversationKey
                        )
                        self.onMCPAuthFailure?()
                    }
                    return
                }

                // Intercept responses where Claude itself reports the MCP is not
                // connected / needs re-auth (exit 0 but content signals failure).
                if useOfficialMCP, self.looksLikeMCPNotConnectedResponse(outputText) {
                    SessionDebugLogger.log("claude-cli", "MCP not-connected detected in response text — failing turn and firing onMCPAuthFailure")
                    DispatchQueue.main.async {
                        self.failTurn(
                            "The archive isn't connected — your auth token may have expired or needs to be set up.",
                            conversationKey: conversationKey
                        )
                        self.onMCPAuthFailure?()
                    }
                    return
                }
                // Successful turn via token injection — the reconnect is resolved.
                if useOfficialMCP, officialMCPToken != nil, AppSettings.mcpReconnectNeeded {
                    DispatchQueue.main.async { AppSettings.mcpReconnectNeeded = false }
                }
                self.finishCLIResponse(outputText, conversationKey: conversationKey)
                return
            }
            // Non-zero exit: check for auth errors before treating as generic failure.
            if useOfficialMCP, self.looksLikeMCPAuthFailure(stdout: stdout, stderr: stderr) {
                SessionDebugLogger.log("claude-cli", "MCP auth failure detected — failing turn and firing onMCPAuthFailure")
                DispatchQueue.main.async {
                    self.failTurn(
                        "The archive isn't connected — your auth token may have expired or needs to be set up.",
                        conversationKey: conversationKey
                    )
                    self.onMCPAuthFailure?()
                }
                return
            }

            let errorText = self.normalizeCLIError(stdout: stdout, stderr: stderr, fallback: "Claude Code CLI could not complete the request.")
            self.failTurn(errorText, conversationKey: conversationKey)
        }
    }

    func callCodexCLI(executablePath: String, message: String, attachments: [SessionAttachment], environment: [String: String], expert: ResponderExpert?, conversationKey: String, archiveContext: String?, useOfficialMCP: Bool) {
        let modelLabel = selectedCodexModelLabel()
        let planningSummary = useOfficialMCP
            ? "Calling \(modelLabel) in Codex with Lenny MCP"
            : "Calling \(modelLabel) in Codex"
        onToolUse?("Planning", ["summary": planningSummary])
        appendHistory(Message(role: .toolUse, text: "Planning: \(planningSummary)"), to: conversationKey)

        let prompt = buildConversationPrompt(message: message, attachments: attachments, expert: expert, conversationKey: conversationKey, archiveContext: archiveContext, expectMCP: useOfficialMCP)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("lenny-codex-last-message-\(UUID().uuidString).md")
        var runtimeEnvironment = environment
        if let token = officialMCPToken(from: environment) {
            runtimeEnvironment[Constants.lennyMCPAuthEnvVar] = token
        }

        let approvalPolicy = useOfficialMCP ? "on-request" : "never"
        var args = [
            "-a",
            approvalPolicy,
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

        if useOfficialMCP, let token = officialMCPToken(from: environment) {
            // Inject MCP config only when we have a bearer token from Settings/env.
            // When the native path is used (token == nil), Codex reads its own .codex/config.toml.
            args.append(contentsOf: [
                "-c",
                "mcp_servers.\(Constants.lennyMCPServerLabel).url=\"\(Constants.lennyMCPURL)\""
            ])

            if AppSettings.officialLennyMCPToken != nil {
                args.append(contentsOf: [
                    "-c",
                    "mcp_servers.\(Constants.lennyMCPServerLabel).http_headers.Authorization=\"Bearer \(token)\""
                ])
            } else {
                args.append(contentsOf: [
                    "-c",
                    "mcp_servers.\(Constants.lennyMCPServerLabel).bearer_token_env_var=\"\(Constants.lennyMCPAuthEnvVar)\""
                ])
            }
        }

        args.append(prompt)

        for attachment in attachments where attachment.kind == .image {
            args.insert(contentsOf: ["-i", attachment.url.path], at: args.count - 1)
        }

        SessionDebugLogger.logMultiline(
            "codex-cli",
            header: "dispatching Codex CLI. executable=\(executablePath) useOfficialMCP=\(useOfficialMCP) args=\(args)",
            body: prompt
        )

        runProcess(
            executablePath: executablePath,
            arguments: args,
            environment: runtimeEnvironment,
            workingDirectory: preferredWorkingDirectoryURL(),
            wantsInteractiveInput: useOfficialMCP,
            allocatePseudoTerminal: useOfficialMCP,
            onLineReceived: { [weak self] line in
                guard let self, !self.isCancellingTurn else { return }
                SessionDebugLogger.trace("codex-transport", line)
                if self.handleApprovalPromptLine(line) {
                    return
                }

                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let event = self.codexCLIStreamEvent(from: json) {
                    let experts = self.expertsFromTransport(
                        payload: json,
                        textCandidates: [event.summary, line]
                    )
                    self.onToolUse?(event.title, ["summary": event.summary, "experts": experts])
                    return
                }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if self.shouldIgnoreCodexTransportLine(trimmed) {
                    return
                }

                let summary = String(trimmed.prefix(80))
                let experts = self.expertsFromTransport(
                    payload: ["message": trimmed],
                    textCandidates: [trimmed, summary]
                )
                self.onToolUse?("Calling Model", ["summary": summary, "experts": experts])
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

            if useOfficialMCP, self.looksLikeMCPAuthFailure(stdout: stdout, stderr: stderr) {
                SessionDebugLogger.log("codex-cli", "MCP auth failure detected — failing turn and firing onMCPAuthFailure")
                DispatchQueue.main.async {
                    self.failTurn(
                        "The archive isn't connected — your auth token may have expired or needs to be set up.",
                        conversationKey: conversationKey
                    )
                    self.onMCPAuthFailure?()
                }
                return
            }

            let errorText = self.normalizeCLIError(stdout: stdout, stderr: stderr, fallback: "Codex CLI could not complete the request.")
            self.failTurn(errorText, conversationKey: conversationKey)
        }
    }

    // MARK: - MCP auth-failure detection

    /// Detects when Claude's response TEXT itself indicates the MCP server is not
    /// connected or needs re-authentication (the CLI exits 0 but the content signals failure).
    func looksLikeMCPNotConnectedResponse(_ text: String) -> Bool {
        let lowered = text.lowercased()

        // Group A: signals that the archive/connection is not ready
        let stateSignals = [
            "not connected",
            "isn't connected",
            "is not connected",
            "isn't authenticated",
            "not authenticated",
            "not yet authenticated",
            "connection isn't",
            "archive isn't",
            "tools aren't available",
            "tools are not available",
            "mcp tools aren't",
            "archive tools aren't",
            "not available in this session",
            "weren't able to reach",
            "wasn't able to reach"
        ]

        // Group B: signals that the user needs to take an auth action
        let actionSignals = [
            "/mcp",            // covers "run /mcp", "type `/mcp`", etc.
            "authenticate",
            "authorization",
            "authorization flow",
            "connect the archive",
            "archive server",   // "check that the archive server is connected"
            "reconnect"
        ]

        // Require at least one signal from each group to fire the banner.
        let hasStateSignal  = stateSignals.contains  { lowered.contains($0) }
        let hasActionSignal = actionSignals.contains { lowered.contains($0) }
        return hasStateSignal && hasActionSignal
    }

    func looksLikeMCPAuthFailure(stdout: String, stderr: String) -> Bool {
        let combined = "\(stdout)\n\(stderr)".lowercased()
        let patterns = [
            "401", "403",
            "unauthorized", "unauthenticated",
            "token expired", "token has expired",
            "authentication failed", "authentication error",
            "invalid token", "access denied",
            "forbidden"
        ]
        return patterns.contains(where: combined.contains)
    }
}

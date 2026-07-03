import Darwin
import Foundation

extension ClaudeSession {
    func start() {
        guard !isRunning else {
            SessionDebugLogger.log("session", "start() called but already running — ignoring")
            return
        }
        isRunning = true
        SessionDebugLogger.log("session", "start() called")
        logStartupDiagnostics()
        resolvePreferredBackend { [weak self] backend, environment, message in
            guard let self else { return }
            SessionDebugLogger.log("session", "start() backend resolution completed. backend=\(String(describing: backend)) environment=\(SessionDebugLogger.summarizeEnvironment(environment))")
            self.hasResolvedBackendOnce = true
            guard let backend else {
                let msg = message ?? self.backendSetupMessage(environment: environment)
                SessionDebugLogger.log("session", "start() failed: \(msg)")
                self.isRunning = false
                self.lastSetupRequiredMessage = msg
                self.onSetupRequired?(msg)
                return
            }

            self.selectedBackend = backend
            self.lastSetupRequiredMessage = nil
            SessionDebugLogger.log("session", "session ready. selectedBackend=\(self.backendStatusMessage(for: backend, environment: environment))")
            self.onSessionReady?()
        }
    }

    func send(message: String, attachments: [SessionAttachment] = []) {
        let activeExpert = focusedExpert
        let conversationKey = key(for: activeExpert)
        isCancellingTurn = false
        pendingExperts.removeAll()
        liveToolCallsByID.removeAll()
        assistantExplicitlyRequestedExperts = false
        appendHistory(Message(role: .user, text: historyText(message: message, attachments: attachments)), to: conversationKey)
        isBusy = true
        SessionDebugLogger.logMultiline(
            "turn",
            header: "send() called. conversationKey=\(conversationKey) expert=\(activeExpert?.name ?? "none") archiveMode=\(AppSettings.effectiveArchiveAccessMode.rawValue) attachments=\(SessionDebugLogger.summarizeAttachments(attachments))",
            body: "User message:\n\(message)"
        )

        resolvePreferredBackend { [weak self] backend, environment, messageText in
            guard let self else { return }
            guard !self.isCancellingTurn else {
                self.isBusy = false
                return
            }
            SessionDebugLogger.log("turn", "resolved backend=\(String(describing: backend)) environment=\(SessionDebugLogger.summarizeEnvironment(environment))")
            guard let backend else {
                SessionDebugLogger.log("turn", "backend resolution failed: \(messageText ?? "unknown error")")
                self.isBusy = false
                self.onSetupRequired?(messageText ?? self.backendSetupMessage(environment: environment))
                return
            }

            self.selectedBackend = backend
            let archiveMode = self.effectiveArchiveAccessMode(environment: environment)
            let status = self.backendStatusMessage(for: backend, environment: environment)
            self.onToolResult?(status, false)
            self.appendHistory(Message(role: .toolResult, text: status), to: conversationKey)

            let sourceSummary = archiveMode == .starterPack
                ? "Source: Lenny's public archive (GitHub)"
                : "Source: Official archive"
            self.onToolResult?(sourceSummary, false)
            self.appendHistory(Message(role: .toolResult, text: sourceSummary), to: conversationKey)

            if archiveMode == .starterPack {
                switch backend {
                case .openAIResponsesAPI:
                    guard let key = environment["OPENAI_API_KEY"], !key.isEmpty else {
                        SessionDebugLogger.log("turn", "starter pack openai fallback but OPENAI_API_KEY missing")
                        self.failTurn(self.backendSetupMessage(environment: environment), conversationKey: conversationKey)
                        return
                    }
                    SessionDebugLogger.log("archive", "openai path: pre-fetching GitHub archive. expert=\(activeExpert?.name ?? "none")")
                    self.prefetchGitHubArchiveContext(message: message, expert: activeExpert, conversationKey: conversationKey) { [weak self] context in
                        guard let self else { return }
                        self.callOpenAI(
                            message: message,
                            attachments: attachments,
                            apiKey: key,
                            expert: activeExpert,
                            conversationKey: conversationKey,
                            mcpToken: nil,
                            archiveContext: context.isEmpty ? nil : context
                        )
                    }

                case let .claudeCodeCLI(path):
                    let archiveContext = self.githubArchiveContext(for: backend, expert: activeExpert)
                    SessionDebugLogger.log("archive", "using GitHub archive context (CLI). backend=\(backend) expert=\(activeExpert?.name ?? "none")")
                    self.onToolUse?("Searching archive", ["summary": "Fetching from Lenny's public archive"])
                    self.appendHistory(Message(role: .toolUse, text: "Searching archive"), to: conversationKey)
                    self.onToolResult?("Archive ready", false)
                    self.appendHistory(Message(role: .toolResult, text: "Archive ready"), to: conversationKey)
                    self.callClaudeCodeCLI(
                        executablePath: path,
                        message: message,
                        attachments: attachments,
                        environment: environment,
                        expert: activeExpert,
                        conversationKey: conversationKey,
                        archiveContext: archiveContext,
                        officialMCPToken: nil,
                        useOfficialMCP: false
                    )

                case let .codexCLI(path):
                    let archiveContext = self.githubArchiveContext(for: backend, expert: activeExpert)
                    SessionDebugLogger.log("archive", "using GitHub archive context (Codex). backend=\(backend) expert=\(activeExpert?.name ?? "none")")
                    self.onToolUse?("Searching archive", ["summary": "Fetching from Lenny's public archive"])
                    self.appendHistory(Message(role: .toolUse, text: "Searching archive"), to: conversationKey)
                    self.onToolResult?("Archive ready", false)
                    self.appendHistory(Message(role: .toolResult, text: "Archive ready"), to: conversationKey)
                    self.callCodexCLI(
                        executablePath: path,
                        message: message,
                        attachments: attachments,
                        environment: environment,
                        expert: activeExpert,
                        conversationKey: conversationKey,
                        archiveContext: archiveContext,
                        useOfficialMCP: false
                    )
                }
                return
            }

            // ── Native CLI MCP path ────────────────────────────────────────────────────
            // The CLI already has Lenny MCP configured with its own credentials;
            // invoke it directly without injecting a token or fetching context via HTTP.
            //
            // Yield to token injection when the user has an explicit settings/env token.
            // This covers the expired-token recovery case: after the banner install the
            // native config file may still hold a stale token, while the settings token
            // is fresh. Token injection writes a temp --mcp-config with --strict-mcp-config
            // so only the fresh bearer-token server is loaded, bypassing stale entries.
            let hasExplicitToken = self.officialMCPToken(from: environment) != nil
            if archiveMode == .officialMCP, self.backendHasNativeMCPConfiguration(backend), !hasExplicitToken {
                SessionDebugLogger.log("archive", "native MCP path: backend=\(backend) — dispatching with useOfficialMCP=true, no token injection")
                self.onToolUse?("Connecting to archive", ["summary": "Connecting to the official archive"])
                self.appendHistory(Message(role: .toolUse, text: "Connecting to archive"), to: conversationKey)
                self.onToolResult?("Archive ready", false)
                self.appendHistory(Message(role: .toolResult, text: "Archive ready"), to: conversationKey)
                self.dispatchResolvedBackend(
                    backend,
                    message: message,
                    attachments: attachments,
                    environment: environment,
                    expert: activeExpert,
                    conversationKey: conversationKey,
                    archiveContext: nil,
                    officialMCPToken: nil,
                    useOfficialMCP: true
                )
                return
            }

            // ── Settings / env bearer-token MCP path ───────────────────────────────
            // Also reached when native config exists but user has a settings token
            // (hasExplicitToken bypassed the native path above).
            if let token = self.officialMCPToken(from: environment) {
                // For both CLI backends, inject the token directly via the CLI's own
                // MCP config mechanism. This is strictly better than HTTP pre-fetch:
                // Claude can call multiple MCP tools interactively rather than getting
                // a single pre-fetched context blob. It also bypasses any stale OAuth
                // entries in the native config (--strict-mcp-config loads only ours).
                if case .claudeCodeCLI = backend {
                    SessionDebugLogger.log("archive", "claude CLI settings token: injecting via --mcp-config --strict-mcp-config. token=\(String(token.prefix(8)))...")
                    self.onToolUse?("Connecting to archive", ["summary": "Connecting to the official archive"])
                    self.appendHistory(Message(role: .toolUse, text: "Connecting to archive"), to: conversationKey)
                    self.onToolResult?("Archive ready", false)
                    self.appendHistory(Message(role: .toolResult, text: "Archive ready"), to: conversationKey)
                    self.dispatchResolvedBackend(
                        backend,
                        message: message,
                        attachments: attachments,
                        environment: environment,
                        expert: activeExpert,
                        conversationKey: conversationKey,
                        archiveContext: nil,
                        officialMCPToken: token,
                        useOfficialMCP: true
                    )
                    return
                }

                if case .codexCLI = backend, self.backendSupportsOfficialMCP(backend, environment: environment) {
                    self.dispatchResolvedBackend(
                        backend,
                        message: message,
                        attachments: attachments,
                        environment: environment,
                        expert: activeExpert,
                        conversationKey: conversationKey,
                        archiveContext: nil,
                        officialMCPToken: token,
                        useOfficialMCP: true
                    )
                    return
                }

                // OpenAI backend: no CLI to inject into, so HTTP pre-fetch is the only option.
                self.fetchOfficialArchiveContext(
                    message: message,
                    expert: activeExpert,
                    token: token,
                    conversationKey: conversationKey
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .failure(let error):
                        let normalizedError = self.normalizedLennyMCPAuthError(from: error.localizedDescription) ?? error.localizedDescription
                        self.failTurn(normalizedError, conversationKey: conversationKey)

                    case let .success(officialResult):
                        self.pendingExperts = officialResult.experts
                        SessionDebugLogger.log(
                            "experts",
                            "staged \(officialResult.experts.count) official-archive expert candidate(s) until response completion"
                        )
                        self.dispatchResolvedBackend(
                            backend,
                            message: message,
                            attachments: attachments,
                            environment: environment,
                            expert: activeExpert,
                            conversationKey: conversationKey,
                            archiveContext: officialResult.promptContext,
                            officialMCPToken: nil,
                            useOfficialMCP: false
                        )
                    }
                }
                return
            }

            // No explicit MCP token — fall back to GitHub archive rather than attempting
            // MCP via the global config (which may time out or lack auth).
            SessionDebugLogger.log("archive", "no MCP token, using GitHub archive fallback")

            switch backend {
            case .openAIResponsesAPI:
                guard let key = environment["OPENAI_API_KEY"], !key.isEmpty else {
                    self.failTurn(self.backendSetupMessage(environment: environment), conversationKey: conversationKey)
                    return
                }
                SessionDebugLogger.log("archive", "openai path: pre-fetching GitHub archive. expert=\(activeExpert?.name ?? "none")")
                self.prefetchGitHubArchiveContext(message: message, expert: activeExpert, conversationKey: conversationKey) { [weak self] context in
                    guard let self else { return }
                    self.callOpenAI(
                        message: message,
                        attachments: attachments,
                        apiKey: key,
                        expert: activeExpert,
                        conversationKey: conversationKey,
                        mcpToken: nil,
                        archiveContext: context.isEmpty ? nil : context
                    )
                }

            case let .claudeCodeCLI(path):
                let archiveContext = self.githubArchiveContext(for: backend, expert: activeExpert)
                self.onToolUse?("Searching archive", ["summary": "Fetching from Lenny's public archive"])
                self.appendHistory(Message(role: .toolUse, text: "Searching archive"), to: conversationKey)
                self.onToolResult?("Archive ready", false)
                self.appendHistory(Message(role: .toolResult, text: "Archive ready"), to: conversationKey)
                self.callClaudeCodeCLI(
                    executablePath: path,
                    message: message,
                    attachments: attachments,
                    environment: environment,
                    expert: activeExpert,
                    conversationKey: conversationKey,
                    archiveContext: archiveContext,
                    officialMCPToken: nil,
                    useOfficialMCP: false
                )
            case let .codexCLI(path):
                let archiveContext = self.githubArchiveContext(for: backend, expert: activeExpert)
                self.onToolUse?("Searching archive", ["summary": "Fetching from Lenny's public archive"])
                self.appendHistory(Message(role: .toolUse, text: "Searching archive"), to: conversationKey)
                self.onToolResult?("Archive ready", false)
                self.appendHistory(Message(role: .toolResult, text: "Archive ready"), to: conversationKey)
                self.callCodexCLI(
                    executablePath: path,
                    message: message,
                    attachments: attachments,
                    environment: environment,
                    expert: activeExpert,
                    conversationKey: conversationKey,
                    archiveContext: archiveContext,
                    useOfficialMCP: false
                )
            }
        }
    }

    func terminate() {
        currentProcess?.terminate()
        currentProcess = nil
        currentDataTask?.cancel()
        currentDataTask = nil
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        isRunning = false
        isBusy = false
        livePresenceExperts.removeAll()
        liveToolCallsByID.removeAll()
        onProcessExit?()
    }

    func cancelActiveTurn() {
        isCancellingTurn = true
        if let process = currentProcess {
            let processID = process.processIdentifier
            if process.isRunning {
                // SIGKILL the process and its entire process group immediately.
                // claude (Node.js) and codex ignore SIGINT/SIGTERM, and codex
                // runs wrapped in /usr/bin/script so we must kill the group.
                kill(processID, SIGKILL)
                kill(-processID, SIGKILL)
            }
        }
        currentProcess = nil
        currentDataTask?.cancel()
        currentDataTask = nil
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        isBusy = false
        pendingExperts.removeAll()
        assistantExplicitlyRequestedExperts = false
        livePresenceExperts.removeAll()
        liveToolCallsByID.removeAll()
    }

    private func dispatchResolvedBackend(
        _ backend: Backend,
        message: String,
        attachments: [SessionAttachment],
        environment: [String: String],
        expert: ResponderExpert?,
        conversationKey: String,
        archiveContext: String?,
        officialMCPToken: String?,
        useOfficialMCP: Bool
    ) {
        switch backend {
        case let .claudeCodeCLI(path):
            self.callClaudeCodeCLI(
                executablePath: path,
                message: message,
                attachments: attachments,
                environment: environment,
                expert: expert,
                conversationKey: conversationKey,
                archiveContext: archiveContext,
                officialMCPToken: officialMCPToken,
                useOfficialMCP: useOfficialMCP
            )

        case let .codexCLI(path):
            self.callCodexCLI(
                executablePath: path,
                message: message,
                attachments: attachments,
                environment: environment,
                expert: expert,
                conversationKey: conversationKey,
                archiveContext: archiveContext,
                useOfficialMCP: useOfficialMCP
            )

        case .openAIResponsesAPI:
            guard let key = environment["OPENAI_API_KEY"], !key.isEmpty else {
                SessionDebugLogger.log("turn", "selected openai backend but OPENAI_API_KEY missing")
                self.failTurn(self.backendSetupMessage(environment: environment), conversationKey: conversationKey)
                return
            }
            self.callOpenAI(
                message: message,
                attachments: attachments,
                apiKey: key,
                expert: expert,
                conversationKey: conversationKey,
                mcpToken: useOfficialMCP ? officialMCPToken : nil,
                archiveContext: archiveContext
            )
        }
    }
}

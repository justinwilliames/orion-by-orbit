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
            header: "send() called. conversationKey=\(conversationKey) expert=\(activeExpert?.name ?? "none") attachments=\(SessionDebugLogger.summarizeAttachments(attachments))",
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
            let status = self.backendStatusMessage(for: backend, environment: environment)
            self.onToolResult?(status, false)
            self.appendHistory(Message(role: .toolResult, text: status), to: conversationKey)

            // Orion is single-persona: no archive retrieval, no official MCP.
            // Dispatch the selected backend directly. The `archiveContext`
            // parameter is retained for upstream signature compatibility but
            // is nil (and ignored downstream in buildConversationPrompt).
            switch backend {
            case .openAIResponsesAPI:
                guard let key = environment["OPENAI_API_KEY"], !key.isEmpty else {
                    SessionDebugLogger.log("turn", "openai backend but OPENAI_API_KEY missing")
                    self.failTurn(self.backendSetupMessage(environment: environment), conversationKey: conversationKey)
                    return
                }
                self.callOpenAI(
                    message: message,
                    attachments: attachments,
                    apiKey: key,
                    expert: activeExpert,
                    conversationKey: conversationKey,
                    mcpToken: nil,
                    archiveContext: nil
                )

            case let .claudeCodeCLI(path):
                self.callClaudeCodeCLI(
                    executablePath: path,
                    message: message,
                    attachments: attachments,
                    environment: environment,
                    expert: activeExpert,
                    conversationKey: conversationKey,
                    archiveContext: nil,
                    officialMCPToken: nil,
                    useOfficialMCP: false
                )

            case let .codexCLI(path):
                self.callCodexCLI(
                    executablePath: path,
                    message: message,
                    attachments: attachments,
                    environment: environment,
                    expert: activeExpert,
                    conversationKey: conversationKey,
                    archiveContext: nil,
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

}

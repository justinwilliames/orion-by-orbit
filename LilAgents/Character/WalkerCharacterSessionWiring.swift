import AppKit

extension WalkerCharacter {
    func wireSession(_ session: ClaudeSession) {
        terminalView?.onApprovalResponse = { [weak session] choice in
            session?.submitApprovalChoice(choice)
        }

        session.onSessionReady = { [weak self] in
            guard let self, let terminalView = self.terminalView else { return }
            let wasRequiringSetup = terminalView.requiresInitialConnectionSetup
            terminalView.requiresInitialConnectionSetup = false
            terminalView.endStreaming()
            if terminalView.isShowingInitialWelcomeState, self.focusedExpert == nil, wasRequiringSetup {
                terminalView.showWelcomeGreeting(forceRefresh: true)
            }
        }

        session.onSetupRequired = { [weak self] _ in
            self?.stopLiveStatusFallback()
            self?.setCurrentActivityStatus("")
            self?.claudeSession?.isBusy = false
            self?.claudeSession?.pendingExperts.removeAll()
            self?.claudeSession?.assistantExplicitlyRequestedExperts = false
            if let terminalView = self?.terminalView {
                terminalView.endStreaming()
                terminalView.clearLiveStatus()
                terminalView.requiresInitialConnectionSetup = true
                if self?.focusedExpert == nil {
                    terminalView.showWelcomeGreeting(forceRefresh: true)
                }
            }
            self?.updateExpertNameTag()
        }

        session.onTextDelta = { [weak self] delta in
            guard let self, let tv = self.terminalView else { return }
            tv.appendStreamingText(delta)
        }

        session.onText = { [weak self] text in
            guard let self, let tv = self.terminalView else { return }
            let trimmedIncoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCurrent = tv.currentAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)

            if tv.currentAssistantText.isEmpty {
                tv.appendStreamingText(text)
                return
            }

            guard trimmedIncoming != trimmedCurrent else { return }

            tv.currentAssistantText = text
            let formatted = TerminalMarkdownRenderer.render(text, theme: tv.theme)
            if let lastBubble = tv.transcriptStack.arrangedSubviews.last as? ChatBubbleView {
                lastBubble.setText(formatted)
                let isNearBottom: Bool = {
                    tv.resizeTranscriptToFitContent()
                    guard let docView = tv.scrollView.documentView else { return true }
                    let visibleHeight = tv.scrollView.contentSize.height
                    let maxOffsetY = max(0, docView.bounds.height - visibleHeight)
                    let currentOffsetY = tv.scrollView.contentView.bounds.origin.y
                    return maxOffsetY - currentOffsetY <= 72
                }()
                if isNearBottom {
                    tv.scrollLatestBubbleIntoView()
                }
            } else {
                tv.appendStreamingText(text)
            }
        }

        session.onTurnComplete = { [weak self] in
            guard let self else { return }
            let stagedExperts = self.terminalView?.deferredExpertSuggestions ?? []
            SessionDebugLogger.log("ui", "onTurnComplete fired. focusedExpert=\(self.focusedExpert?.name ?? "none") stagedExperts=\(stagedExperts.map(\.name).joined(separator: ", "))")
            self.stopLiveStatusFallback()
            self.setCurrentActivityStatus("")
            self.terminalView?.endStreaming()
            self.terminalView?.clearLiveStatus()
            self.playCompletionSound()
            self.showCompletionBubble()
            self.updateExpertNameTag()
            if self.focusedExpert != nil {
                self.terminalView?.hideExpertSuggestions(clearState: false)
            } else if !stagedExperts.isEmpty,
                      let session = self.claudeSession {
                let alreadyRenderedExperts = session.history(for: nil).contains { $0.role == .assistant && $0.followUpExpert != nil }
                if !alreadyRenderedExperts {
                    let names = stagedExperts.map(\.name).joined(separator: ", ")
                    session.appendExpertSuggestionEntry(stagedExperts, for: nil)
                    SessionDebugLogger.log("ui", "appended expert suggestion prompt to transcript: \(names)")
                }
            }
            if let session = self.claudeSession {
                self.terminalView?.replayConversation(
                    session.history(for: self.focusedExpert),
                    expertSuggestions: session.expertSuggestionEntries(for: self.focusedExpert)
                )
                session.livePresenceExperts = []
            }
            self.terminalView?.deferredExpertSuggestions = []

            // Generate two follow-up chips. Skipped on expert focus
            // (those flows have their own suggestion UI), and bailed
            // out on chitchat replies under 40 words — no point asking
            // the model to suggest follow-ups to a "got it" response.
            self.scheduleFollowUpGeneration()

            // Run the long-term memory extractor on the just-completed
            // exchange. Fire-and-forget — runs on a background queue,
            // applies the sensitivity filter, only persists what passes.
            // The extractor itself checks the auto-extract toggle and
            // bails on chitchat / missing CLI.
            //
            // NB: conversation transcripts are deliberately NOT
            // persisted — by design Orion chats are fleeting.
            // Only durable user-fact memories live across launches.
            if let session = self.claudeSession {
                let history = session.history(for: self.focusedExpert)
                let lastUser = history.last(where: { $0.role == .user })?.text ?? ""
                let lastAssistant = history.last(where: { $0.role == .assistant })?.text ?? ""
                MemoryExtractor.extract(
                    userMessage: lastUser,
                    assistantReply: lastAssistant,
                    priorMemoryDigest: MemoryStore.all().prefix(10).map(\.name).joined(separator: " · ")
                )
            }
        }

        session.onError = { [weak self] text in
            self?.stopLiveStatusFallback()
            self?.setCurrentActivityStatus("")
            self?.terminalView?.endStreaming()
            self?.terminalView?.clearLiveStatus()
            self?.terminalView?.appendError(text)
            self?.updateExpertNameTag()
        }

        session.onToolUse = { [weak self] toolName, input in
            guard let self else { return }
            let summary = self.formatToolInput(input)
            let explicitExperts = input["experts"] as? [ResponderExpert] ?? []
            let experts = self.mergedLiveExperts(explicitExperts, from: summary)
            let liveStatus = self.formatLiveStatus(toolName: toolName, summary: summary)
            self.noteLiveStatusEvent()
            self.setCurrentActivityStatus(liveStatus)
            self.terminalView?.setLiveStatus(liveStatus, isBusy: true, isError: false, experts: experts)
            self.updateExpertNameTag()

            if toolName.lowercased().contains("planning") {
                self.startLiveStatusFallback()
            }
        }

        session.onToolResult = { [weak self] summary, isError in
            if let self {
                self.noteLiveStatusEvent()
                let liveSummary = self.formatLiveResultStatus(summary, isError: isError)
                if !liveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.setCurrentActivityStatus(liveSummary)
                } else {
                    SessionDebugLogger.log("avatar-status", "ignored empty tool result summary while busy")
                }
                if isError {
                    self.stopLiveStatusFallback()
                }
                let experts = self.mergedLiveExperts([], from: summary)
                self.terminalView?.appendToolResult(summary: summary, displaySummary: liveSummary, isError: isError, experts: experts)
                self.updateExpertNameTag()
                return
            }
        }

        session.onProcessExit = { [weak self] in
            self?.stopLiveStatusFallback()
            self?.terminalView?.endStreaming()
            self?.terminalView?.clearLiveStatus()
            self?.terminalView?.appendError("Archive session ended.")
        }

        session.onExpertsUpdated = { [weak self] experts in
            guard let self else { return }
            self.terminalView?.deferredExpertSuggestions = experts
            let names = experts.map(\.name).joined(separator: ", ")
            SessionDebugLogger.log("ui", "onExpertsUpdated received \(experts.count) expert(s): \(names)")
        }

        session.onApprovalRequested = { [weak self] request in
            guard let self else { return }
            self.noteLiveStatusEvent()
            self.setCurrentActivityStatus("Waiting for approval")
            self.terminalView?.setLiveStatus("Waiting for approval", isBusy: true, isError: false, experts: self.claudeSession?.livePresenceExperts ?? [])
            self.terminalView?.setApprovalRequest(request)
            self.updateExpertNameTag()
        }

        session.onApprovalCleared = { [weak self] in
            self?.terminalView?.clearApprovalRequest()
        }

        // Orion: the archive auth-failure flow is intentionally a no-op.
        // Orion doesn't use the upstream archive at all, and the session
        // parser sometimes mis-classifies "no archive MCP detected" (which is
        // always true for us) as "archive auth failed", which used to call
        // failTurn (chat shows error) and display the auth-key prompt. Both
        // behaviours are wrong here.
        session.onMCPAuthFailure = {}
    }

    func setCurrentActivityStatus(_ status: String) {
        currentActivityStatus = status

        let compact = compactLiveStatus(status)
        if compact.isEmpty {
            SessionDebugLogger.trace("avatar-status", "cleared")
        } else {
            SessionDebugLogger.trace("avatar-status", "showing \(compact)")
        }
    }

    func noteLiveStatusEvent() {
        lastLiveStatusEventAt = Date()
    }

    func extractLiveExperts(from text: String) -> [ResponderExpert] {
        guard let session = claudeSession else { return [] }
        let fromText = detectedLiveExperts(from: text)
        if !fromText.isEmpty { return fromText }
        return session.livePresenceExperts
    }

    func detectedLiveExperts(from text: String) -> [ResponderExpert] {
        guard let session = claudeSession else { return [] }
        return session.expertsFromAssistantText(text)
    }

    func mergedLiveExperts(_ explicitExperts: [ResponderExpert], from text: String) -> [ResponderExpert] {
        if let focusedExpert {
            claudeSession?.livePresenceExperts = [focusedExpert]
            return [focusedExpert]
        }

        let fromText = detectedLiveExperts(from: text)
        let existing = claudeSession?.livePresenceExperts ?? []

        var merged: [ResponderExpert] = []
        for expert in existing + explicitExperts + fromText where !merged.contains(where: { $0.name == expert.name }) {
            merged.append(expert)
        }

        if !merged.isEmpty {
            claudeSession?.livePresenceExperts = merged
        }

        return merged
    }

    func startLiveStatusFallback() {
        noteLiveStatusEvent()
        liveStatusFallbackIndex = 0

        guard liveStatusFallbackTimer == nil else { return }

        liveStatusFallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.advanceLiveStatusFallbackIfNeeded()
        }

        if let timer = liveStatusFallbackTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopLiveStatusFallback() {
        liveStatusFallbackTimer?.invalidate()
        liveStatusFallbackTimer = nil
        lastLiveStatusEventAt = nil
        liveStatusFallbackIndex = 0
    }

    func advanceLiveStatusFallbackIfNeeded() {
        guard isClaudeBusy else {
            stopLiveStatusFallback()
            return
        }

        let lastEventAt = lastLiveStatusEventAt ?? Date()
        guard Date().timeIntervalSince(lastEventAt) >= 4.5 else { return }

        let genericStatuses = Set([
            "on it…",
            "searching archive",
            "reading",
            "writing answer"
        ])
        let normalizedCurrent = currentActivityStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedCurrent.isEmpty, !genericStatuses.contains(normalizedCurrent) {
            terminalView?.setLiveStatus(currentActivityStatus, isBusy: true, isError: false, experts: claudeSession?.livePresenceExperts ?? [])
            updateExpertNameTag()
            lastLiveStatusEventAt = Date()
            return
        }

        // Single-word human verbs — what a real person doing the work
        // would say they're up to. Sir asked for these to be short and
        // human, not multi-word archive-flavoured phrases.
        let fallbackStatuses = [
            "On it…",
            "Researching…",
            "Reading…",
            "Drafting…",
        ]

        let index = min(liveStatusFallbackIndex, fallbackStatuses.count - 1)
        let nextStatus = fallbackStatuses[index]
        setCurrentActivityStatus(nextStatus)
        terminalView?.setLiveStatus(nextStatus, isBusy: true, isError: false, experts: claudeSession?.livePresenceExperts ?? [])
        updateExpertNameTag()

        if liveStatusFallbackIndex < fallbackStatuses.count - 1 {
            liveStatusFallbackIndex += 1
        }
        lastLiveStatusEventAt = Date()
    }
    func updatePopoverPosition() {
        guard let popover = popoverWindow, isIdleForPopover else { return }
        // Anchor to the screen that owns the Dock (where Orion lives),
        // not NSScreen.main — main returns the screen with the focused
        // window, which on a multi-monitor setup is whichever display
        // the user just clicked. The popover would jump screens with
        // every app switch. controller.activeScreen returns the Dock
        // screen by default; falls back to main if the controller
        // isn't reachable yet.
        guard let screen = controller?.activeScreen ?? NSScreen.main else { return }

        let charFrame = window.frame
        let popoverSize = popover.frame.size
        var x = charFrame.midX - popoverSize.width / 2
        // Tail tip floats just above the top of the character window so it
        // points at the head pixels (the GIF has transparent space above
        // the hair, so +4 reads as "speech coming from above his head").
        let y = charFrame.maxY + 4

        let visibleFrame = screen.visibleFrame
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - popoverSize.width - 4))
        let clampedY = min(y, visibleFrame.maxY - popoverSize.height - 4)

        popover.setFrameOrigin(NSPoint(x: x, y: clampedY))

        // After clamping, the popover may have been bumped sideways
        // to fit on-screen — in which case the tail (drawn at the
        // popover-center by default) would no longer point at the
        // character. Rebuild the bubble outline so the tail tracks
        // the character's actual X.
        rebuildPopoverBubbleShellPath(forSize: popoverSize, animated: false)
    }

    /// X (in popover-local coords) where the tail apex should sit
    /// so it points at the character's head, regardless of how the
    /// popover was clamped to fit on-screen. Returns nil when the
    /// popover hasn't been positioned yet — caller falls back to
    /// popover-center.
    func tailCenterXRelativeToPopover() -> CGFloat? {
        guard let popover = popoverWindow else { return nil }
        let charMidX = window.frame.midX
        let popoverOriginX = popover.frame.minX
        return charMidX - popoverOriginX
    }
}

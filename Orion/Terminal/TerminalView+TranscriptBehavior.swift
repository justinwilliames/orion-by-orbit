import AppKit

extension TerminalView {
    @objc func handleTranscriptBoundsDidChange(_ notification: Notification) {
        guard notification.object as? NSClipView === scrollView.contentView else { return }
        guard isTranscriptNearBottom(threshold: 72) else { return }
        onReachedTranscriptBottom?()
    }

    private func resetWelcomeStateTracking() {
        currentWelcomeSuggestions = []
        lastRenderedWelcomeSignature = nil
    }

    private func clearTranscriptStackViews() {
        let arranged = transcriptStack.arrangedSubviews
        for view in arranged {
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        transcriptSuggestionView = nil
        transcriptLiveStatusView = nil
        transcriptApprovalView = nil
        // followUpChipsView was added after the original three trackers
        // and was missed here — the stack wipe removed the chip view but
        // left the pointer dangling, and the next clearFollowUpChips()
        // would crash trying to remove a view that's no longer in this
        // stack (NSStackView.m:1052 assertion). Symptom: send button on
        // the second message did nothing, exception unwound silently.
        followUpChipsView = nil
    }

    private func isTranscriptNearBottom(threshold: CGFloat = 48) -> Bool {
        resizeTranscriptToFitContent()
        guard let docView = scrollView.documentView else {
            return true
        }

        let visibleHeight = scrollView.contentSize.height
        let maxOffsetY = max(0, docView.bounds.height - visibleHeight)
        let currentOffsetY = scrollView.contentView.bounds.origin.y
        return maxOffsetY - currentOffsetY <= threshold
    }

    private func scrollTranscriptViewIntoView(
        _ view: NSView,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        preferBottomEdge: Bool = false
    ) {
        resizeTranscriptToFitContent()
        guard let docView = scrollView.documentView else {
            return
        }

        let visibleHeight = scrollView.contentSize.height
        let maxOffsetY = max(0, docView.bounds.height - visibleHeight)
        let currentOffsetY = scrollView.contentView.bounds.origin.y
        let targetTopY = max(0, view.frame.minY - topPadding)
        let targetBottomY = min(docView.bounds.height, view.frame.maxY + bottomPadding)

        let nextOffsetY: CGFloat
        if preferBottomEdge, (targetTopY < currentOffsetY || targetBottomY > currentOffsetY + visibleHeight) {
            nextOffsetY = min(maxOffsetY, max(0, targetBottomY - visibleHeight))
        } else if targetTopY < currentOffsetY {
            nextOffsetY = targetTopY
        } else if targetBottomY > currentOffsetY + visibleHeight {
            nextOffsetY = min(maxOffsetY, max(0, targetBottomY - visibleHeight))
        } else {
            return
        }

        docView.scroll(NSPoint(x: 0, y: nextOffsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scrollLatestTranscriptItemIntoView(
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        preferBottomEdge: Bool = false
    ) {
        guard let lastView = transcriptStack.arrangedSubviews.last else {
            scrollToBottom()
            return
        }

        scrollTranscriptViewIntoView(
            lastView,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            preferBottomEdge: preferBottomEdge
        )
    }

    private func appendBubble(
        text: NSAttributedString,
        isUser: Bool,
        speaker: TranscriptSpeaker,
        followUpExpert: ResponderExpert? = nil,
        textInsets: NSSize = NSSize(width: 14, height: 12),
        showsCopyAction: Bool = true,
        showsSpeakerHeader: Bool = true,
        markdownSource: String? = nil
    ) {
        let followUpHandler: (() -> Void)? = {
            guard let followUpExpert, !self.isExpertMode else { return nil }
            return { [weak self] in
                guard let self else { return }
                self.onSelectExpert?(followUpExpert)
            }
        }()

        let bubble = ChatBubbleView(
            text: text,
            isUser: isUser,
            speaker: speaker,
            theme: theme,
            showsSpeakerHeader: showsSpeakerHeader,
            textInsets: textInsets,
            markdownSource: markdownSource,
            onCopy: showsCopyAction ? {
                WalkerCharacter.playSelectionSound()
            } : nil,
            onFollowUp: followUpHandler
        )
        // Set the column-aware max width before adding to the stack
        // so the bubble's first render lands at the correct size.
        // Without this every new bubble renders at the 380pt default
        // for one frame and only corrects when the next layout pass
        // runs propagateBubbleMaxWidth — which left expanded-mode
        // bubbles stuck at the narrow default size.
        bubble.maxBubbleWidth = currentBubbleMaxWidth()
        transcriptStack.addArrangedSubview(bubble)
        bubble.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
        if !isReplayingTranscript {
            scrollTranscriptViewIntoView(bubble, topPadding: 12, bottomPadding: 28, preferBottomEdge: true)
        }
    }

    func expertSuggestionCardHeight(for expertCount: Int) -> CGFloat {
        let count = CGFloat(expertCount)
        return 30 + (count * 54) + max(0, count - 1) * 8
    }

    private func appendSuggestionEntryView(_ entry: ExpertSuggestionEntry) {
        if entry.isCollapsed, entry.pickedExpert != nil {
            let compact = CompactSuggestionView(theme: theme, entry: entry)
            compact.onRetap = { [weak self] entryID in
                self?.onEditExpertSuggestion?(entryID)
            }
            transcriptStack.addArrangedSubview(compact)
            compact.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
            compact.heightAnchor.constraint(equalToConstant: 46).isActive = true
            return
        }

        let suggestionsView = ExpertSuggestionCardView(theme: theme, entry: entry)
        suggestionsView.onExpertTapped = { [weak self] entryID, expert in
            self?.onSelectExpertSuggestion?(entryID, expert)
        }
        transcriptStack.addArrangedSubview(suggestionsView)
        suggestionsView.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
        suggestionsView.heightAnchor.constraint(equalToConstant: expertSuggestionCardHeight(for: entry.experts.count)).isActive = true
    }

    private func appendStarterPackUpsellCard(compact: Bool = true) {
        if requiresInitialConnectionSetup {
            appendConnectionSetupCard()
            return
        }

        let upsell = StarterPackUpsellCardView(theme: theme, compact: compact)
        upsell.onConnectTapped = { [weak self] in
            self?.appendOfficialMCPSetupCard()
        }
        upsell.onSettingsTapped = { [weak self] in
            self?.openAppSettings()
        }
        transcriptStack.addArrangedSubview(upsell)
        upsell.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true

        if !isReplayingTranscript {
            scrollTranscriptViewIntoView(upsell, topPadding: 12, bottomPadding: 28, preferBottomEdge: true)
        }
    }

    private func appendConnectionSetupCard() {
        let setupCard = ConnectionSetupCardView(theme: theme)
        setupCard.onOpenSettings = { [weak self] in
            self?.openAppSettings()
        }
        transcriptStack.addArrangedSubview(setupCard)
        setupCard.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true

        if !isReplayingTranscript {
            scrollTranscriptViewIntoView(setupCard, topPadding: 12, bottomPadding: 28, preferBottomEdge: true)
        }
    }

    private func appendOfficialMCPSetupCard() {
        // Orion: archive-auth setup card permanently disabled — see
        // showOfficialMCPSetupPanel() in TerminalView+WelcomePanel.swift.
        return
    }

    func showWelcomeGreeting(forceRefresh: Bool = false) {
        ensureWelcomeSuggestionSelection(forceRefresh: forceRefresh || !isShowingInitialWelcomeState)
        let welcomeSignature: String
        if requiresInitialConnectionSetup {
            welcomeSignature = "setup-required"
        } else {
            welcomeSignature = "starterPack|\(shouldPresentStarterPackWelcomeBanner ? "banner" : "chips")"
        }

        if !forceRefresh,
           isShowingInitialWelcomeState,
           lastRenderedWelcomeSignature == welcomeSignature,
           transcriptStack.arrangedSubviews.count == 1,
           transcriptStack.arrangedSubviews.first is ChatBubbleView {
            showWelcomeSuggestionsPanel()
            scrollToTop()
            return
        }

        clearTranscriptSuggestionView()
        clearTranscriptLiveStatus()
        hideWelcomeSuggestionsPanel()
        isShowingInitialWelcomeState = true
        clearTranscriptStackViews()
        currentAssistantText = ""
        let t = theme
        let greeting: String
        if requiresInitialConnectionSetup {
            greeting = "Orion here — Orbit's menu-bar lifecycle assistant. Connect Claude Code or Codex in Settings and we'll get into it."
        } else {
            greeting = "Orion here — Orbit's menu-bar lifecycle assistant. Ask about lifecycle, deliverability, Braze, retention economics — anything from the Orbit playbook. I'll lead with the sharpest answer and go deeper if you want it."
        }
        let attrText = NSAttributedString(string: greeting, attributes: [
            .font: t.font,
            .foregroundColor: t.textPrimary,
        ])
        appendBubble(text: attrText, isUser: false, speaker: TranscriptSpeaker(name: "Orion", avatarPath: nil, kind: .orion))

        lastObservedFirstRunConfigurationSignature = firstRunConfigurationSignature()
        lastRenderedWelcomeSignature = welcomeSignature
        showWelcomeSuggestionsPanel()
        scrollToTop()
    }

    func showExpertGreeting(for expert: ResponderExpert) {
        clearTranscriptSuggestionView()
        hideWelcomeSuggestionsPanel()
        isShowingInitialWelcomeState = false
        resetWelcomeStateTracking()

        let greeting = "I'm \(expert.name). What would you like to dig into?"
        let attrText = NSAttributedString(string: greeting, attributes: [
            .font: theme.font,
            .foregroundColor: theme.textPrimary,
        ])
        clearTranscriptStackViews()
        appendBubble(
            text: attrText,
            isUser: false,
            speaker: TranscriptSpeaker(name: expert.name, title: expert.title, avatarPath: expert.avatarPath, kind: .expert),
            textInsets: NSSize(width: 20, height: 12),
            showsCopyAction: false
        )
        currentAssistantText = ""
        scrollToTop()
    }

    func appendUser(_ text: String, attachments: [SessionAttachment] = []) {
        isShowingInitialWelcomeState = false
        resetWelcomeStateTracking()
        let t = theme
        let visibleText = text.isEmpty ? "Sent with attachment" : text
        let attrText = NSMutableAttributedString(string: visibleText, attributes: [
            .font: t.fontBold,
            .foregroundColor: t.textPrimary
        ])

        if !attachments.isEmpty {
            let attachText = attachments.map(\.displayName).joined(separator: ", ")
            attrText.append(NSAttributedString(string: "\n📎 \(attachText)", attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: t.textDim
            ]))
        }

        appendBubble(
            text: attrText,
            isUser: true,
            speaker: TranscriptSpeaker(name: "You", avatarPath: nil, kind: .user),
            showsSpeakerHeader: false
        )
    }

    func appendStreamingText(_ text: String) {
        var cleaned = text
        if currentAssistantText.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
        }
        currentAssistantText += cleaned
        if !cleaned.isEmpty {
            if let lastBubble = transcriptStack.arrangedSubviews.last as? ChatBubbleView {
                let formatted = TerminalMarkdownRenderer.render(currentAssistantText, theme: theme)
                lastBubble.setText(formatted)
                lastBubble.setMarkdownSource(currentAssistantText)
            } else {
                beginAssistantTurn(name: theme.titleString)
                if let lastBubble = transcriptStack.arrangedSubviews.last as? ChatBubbleView {
                    let formatted = TerminalMarkdownRenderer.render(currentAssistantText, theme: theme)
                    lastBubble.setText(formatted)
                    lastBubble.setMarkdownSource(currentAssistantText)
                }
            }
            // Only scroll if already near bottom; don't force scroll while reading
            if isTranscriptNearBottom(threshold: 72) {
                scrollLatestBubbleIntoView()
            }
        }
    }

    func beginAssistantTurn(name: String?) {
        // Always render the streaming-placeholder bubble as
        // Orion (kind: .orion) so the sparkle avatar shows
        // exactly the same as it does post-response. Earlier this
        // code did `kind: labelName.lowercased() == "orion" ? .orion : .system`,
        // and any theme whose titleString didn't lowercase to
        // exactly "orion" (the upstream LIL-LENNY themes
        // still around for backwards-compat) routed the bubble to
        // `.system`, which renders with a person icon instead of
        // the sparkle. Single-persona app — no reason to detect.
        let labelName = (name?.isEmpty == false) ? name! : "Orion"
        let speaker = TranscriptSpeaker(name: labelName, avatarPath: nil, kind: .orion)
        appendBubble(text: NSAttributedString(string: ""), isUser: false, speaker: speaker)
    }

    func endStreaming() {
        isStreaming = false
    }

    func appendError(_ text: String) {
        let t = theme
        let errorText = NSAttributedString(string: text, attributes: [
            .font: t.font,
            .foregroundColor: t.errorColor
        ])
        appendBubble(text: errorText, isUser: false, speaker: TranscriptSpeaker(name: "System", avatarPath: nil, kind: .system))
    }

    func appendStatus(_ text: String) {
        // Handled entirely by live status pill
    }

    func renderTranscriptLiveStatus(_ text: String, experts: [ResponderExpert] = []) {
        let shouldStickToBottom = isTranscriptNearBottom(threshold: 72)
        if let statusView = transcriptLiveStatusView as? TranscriptStatusView {
            statusView.update(text: text, experts: experts)
        } else {
            let statusView = TranscriptStatusView(theme: theme, text: text, experts: experts)
            transcriptStack.addArrangedSubview(statusView)
            statusView.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
            transcriptLiveStatusView = statusView
        }

        if shouldStickToBottom {
            scrollToBottom()
        } else if let statusView = transcriptLiveStatusView {
            scrollTranscriptViewIntoView(statusView, topPadding: 12, bottomPadding: 20, preferBottomEdge: true)
        }
    }

    func clearTranscriptLiveStatus() {
        if let view = transcriptLiveStatusView {
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
            transcriptLiveStatusView = nil
        }
    }

    func renderTranscriptApproval(_ request: ClaudeSession.ApprovalRequest) {
        let shouldStickToBottom = isTranscriptNearBottom(threshold: 72)
        if let approvalView = transcriptApprovalView as? TranscriptApprovalView {
            approvalView.update(request: request)
        } else {
            let approvalView = TranscriptApprovalView(theme: theme, request: request)
            approvalView.onChoice = { [weak self] choice in
                self?.onApprovalResponse?(choice)
            }
            transcriptStack.addArrangedSubview(approvalView)
            approvalView.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
            transcriptApprovalView = approvalView
        }

        if shouldStickToBottom {
            scrollToBottom()
        } else if let approvalView = transcriptApprovalView {
            scrollTranscriptViewIntoView(approvalView, topPadding: 12, bottomPadding: 20, preferBottomEdge: true)
        }
    }

    func clearTranscriptApproval() {
        if let view = transcriptApprovalView {
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
            transcriptApprovalView = nil
        }
    }

    func appendExpertSuggestion(_ experts: [ResponderExpert]) {
        currentExpertSuggestions = experts
        expertSuggestionsCollapsed = false
        renderTranscriptSuggestions()
    }

    func appendToolUse(toolName: String, summary: String, experts: [ResponderExpert] = []) {
        endStreaming()
        setLiveStatus(toolName, isBusy: true, isError: false, experts: experts)
    }

    func appendToolResult(summary: String, displaySummary: String? = nil, isError: Bool, experts: [ResponderExpert] = []) {
        setLiveStatus(displaySummary ?? summary, isBusy: !isError, isError: isError, experts: experts)
    }

    func replayHistory(
        _ messages: [ClaudeSession.Message],
        restoreStrategy: TranscriptReplayRestoreStrategy = .preserveVisiblePosition
    ) {
        replayConversation(messages, expertSuggestions: [], restoreStrategy: restoreStrategy)
    }

    func replayConversation(
        _ messages: [ClaudeSession.Message],
        expertSuggestions: [ExpertSuggestionEntry],
        restoreStrategy: TranscriptReplayRestoreStrategy = .preserveVisiblePosition
    ) {
        let t = theme
        let previousOffsetY = scrollView.contentView.bounds.origin.y
        let shouldStickToBottom = isTranscriptNearBottom(threshold: 72)
        let unreadBoundaryCount: Int? = {
            guard case .focusUnreadBoundary(let lastReadHistoryCount) = restoreStrategy else { return nil }
            return lastReadHistoryCount
        }()

        isShowingInitialWelcomeState = false
        resetWelcomeStateTracking()
        isReplayingTranscript = true
        clearTranscriptStackViews()
        hideWelcomeSuggestionsPanel()
        currentAssistantText = ""
        var lastRole: ClaudeSession.Message.Role?
        var assistantCount = 0
        let suggestionsByAnchor = Dictionary(grouping: expertSuggestions, by: \.anchorHistoryCount)
        var unreadAnchorView: NSView?

        for (index, msg) in messages.enumerated() {
            let priorSubviewCount = transcriptStack.arrangedSubviews.count
            switch msg.role {
            case .user:
                appendUser(msg.text)
            case .assistant:
                assistantCount += 1
                let speaker = msg.speaker ?? TranscriptSpeaker(name: t.titleString, avatarPath: nil, kind: .orion)
                let formatted = TerminalMarkdownRenderer.render(msg.text, theme: t)
                appendBubble(text: formatted, isUser: false, speaker: speaker, followUpExpert: msg.followUpExpert, markdownSource: msg.text)
            case .error:
                appendError(msg.text)
            case .toolUse:
                continue
            case .toolResult:
                continue
            }
            lastRole = msg.role

            let anchorHistoryCount = index + 1
            if unreadAnchorView == nil,
               let unreadBoundaryCount,
               anchorHistoryCount > unreadBoundaryCount,
               transcriptStack.arrangedSubviews.count > priorSubviewCount {
                unreadAnchorView = transcriptStack.arrangedSubviews.last
            }
            if let entries = suggestionsByAnchor[anchorHistoryCount] {
                for entry in entries {
                    let priorSuggestionSubviewCount = transcriptStack.arrangedSubviews.count
                    appendSuggestionEntryView(entry)
                    if unreadAnchorView == nil,
                       let unreadBoundaryCount,
                       anchorHistoryCount > unreadBoundaryCount,
                       transcriptStack.arrangedSubviews.count > priorSuggestionSubviewCount {
                        unreadAnchorView = transcriptStack.arrangedSubviews.last
                    }
                }
            }
        }

        if shouldShowStarterPackUpsell && assistantCount == 1 && !requiresInitialConnectionSetup {
            appendStarterPackUpsellCard()
        }

        if lastRole == .assistant {
            endStreaming()
        }
        isReplayingTranscript = false
        resizeTranscriptToFitContent()

        switch restoreStrategy {
        case .focusUnreadBoundary(let lastReadHistoryCount):
            if messages.count > lastReadHistoryCount, let unreadAnchorView {
                scrollTranscriptViewIntoView(unreadAnchorView, topPadding: 12, bottomPadding: 28)
            } else {
                scrollToBottom()
            }
        case .preserveVisiblePosition:
            if shouldStickToBottom {
                scrollToBottom()
            } else if let mostRecentBubble = transcriptStack.arrangedSubviews.last(where: { $0 is ChatBubbleView }) {
                // Anchor the TOP of the most recent bubble at the
                // top of the visible area. After a turn completes,
                // the most recent bubble is typically the
                // assistant's reply — Sir wants to read that from
                // the start, not see his own question pinned at
                // the top with the response scrolled past below.
                // Earlier code anchored the last *user* bubble,
                // which produced exactly that wrong behaviour.
                scrollTranscriptViewIntoView(mostRecentBubble, topPadding: 12, bottomPadding: 0)
            } else if let docView = scrollView.documentView {
                let maxOffsetY = max(0, docView.bounds.height - scrollView.contentSize.height)
                let restoredOffsetY = min(previousOffsetY, maxOffsetY)
                docView.scroll(NSPoint(x: 0, y: restoredOffsetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    func scrollToBottom() {
        resizeTranscriptToFitContent()
        if let docView = scrollView.documentView {
            let maxScroll = docView.bounds.height - scrollView.contentSize.height
            if maxScroll > 0 {
                docView.scroll(NSPoint(x: 0, y: maxScroll))
            }
        }
        onReachedTranscriptBottom?()
    }

    func scrollLatestBubbleIntoView() {
        scrollLatestTranscriptItemIntoView(preferBottomEdge: true)
    }

    func scrollToTop() {
        resizeTranscriptToFitContent()
        scrollView.documentView?.scroll(NSPoint(x: 0, y: 0))
    }

    func resizeTranscriptToFitContent() {
        transcriptStack.layoutSubtreeIfNeeded()
        let stackHeight = transcriptStack.fittingSize.height
        let targetHeight = max(scrollView.contentSize.height, stackHeight + 10)
        transcriptContainer.frame.size.height = targetHeight
    }
}

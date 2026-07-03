import AppKit

extension TerminalView {
    @objc func inputSubmitted() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("[Orion] inputSubmitted: text.count=\(text.count) attachments=\(pendingAttachments.count) isStreaming=\(isStreaming) statusVisible=\(!composerStatusLabel.isHidden) firstResponder=\(String(describing: window?.firstResponder))")
        guard !text.isEmpty || !pendingAttachments.isEmpty else {
            NSLog("[Orion] inputSubmitted: bailing — empty text and no attachments")
            return
        }

        if isShowingInitialWelcomeState {
            transcriptStack.arrangedSubviews.forEach { view in
                transcriptStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            transcriptSuggestionView = nil
            transcriptLiveStatusView = nil
            currentAssistantText = ""
            isShowingInitialWelcomeState = false
        }

        hideWelcomeSuggestionsPanel()
        clearTranscriptSuggestionView()
        clearFollowUpChips()

        let attachments = pendingAttachments
        inputField.stringValue = ""
        pendingAttachments.removeAll()
        refreshAttachmentPreviews()

        appendUser(text, attachments: attachments)
        isStreaming = true
        currentAssistantText = ""
        setLiveStatus("Getting things moving…", isBusy: true, isError: false)
        DispatchQueue.main.async { [weak self] in
            self?.scrollToBottom()
        }
        onSendMessage?(text, attachments)
    }

    @objc func sendOrStopTapped() {
        // Defense in depth — Sir's report: "I can't send follow up
        // messages after the initial response from Orion." Hypothesis:
        // a stale-visible composerStatusLabel after the first turn's
        // clearLiveStatus call leaves this button in "Stop" mode even
        // though no turn is in flight, so the button silently triggers
        // onStopRequested instead of sending. If the user has typed
        // text AND we know the local streaming flag is false (turn not
        // active), force the send path regardless of status visibility.
        let hasText = !inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canForceSend = hasText && !isStreaming
        NSLog("[Orion] sendOrStopTapped: statusVisible=\(!composerStatusLabel.isHidden) hasText=\(hasText) isStreaming=\(isStreaming) → \(canForceSend || composerStatusLabel.isHidden ? "send" : "stop")")
        if canForceSend || composerStatusLabel.isHidden {
            inputSubmitted()
        } else {
            onStopRequested?()
        }
    }

    @objc func returnToLennyTapped() {
        onReturnToLenny?()
    }

    @objc func attachButtonTapped() {
        presentAttachmentPicker()
    }

    func updatePlaceholder(_ text: String) {
        placeholderText = text
        guard let paddedCell = inputField.cell as? PaddedTextFieldCell else { return }
        let t = theme
        paddedCell.placeholderAttributedString = NSAttributedString(
            string: text,
            attributes: [.font: t.font, .foregroundColor: t.textDim]
        )
        inputField.needsDisplay = true
    }
}

import AppKit

extension TerminalView {

    @objc func dictateButtonTapped() {
        if isDictating {
            stopDictation()
        } else {
            startDictation()
        }
    }

    /// Begin streaming microphone input through the dictation manager.
    /// Live partial transcripts replace whatever sat in the input field
    /// after the baseline (the text the user had typed before clicking
    /// dictate), so they can speak a follow-on sentence to a half-typed
    /// thought.
    private func startDictation() {
        WalkerCharacter.playSelectionSound()

        // Preserve whatever the user had typed already so live
        // transcripts append to it instead of overwriting.
        dictationBaselineText = inputField.stringValue
        let baselineHasText = !dictationBaselineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let separator = baselineHasText ? " " : ""

        applyDictatingButtonStyle()
        isDictating = true

        dictationManager.start(
            onUpdate: { [weak self] update in
                guard let self else { return }
                self.inputField.stringValue = self.dictationBaselineText + separator + update.transcript
                if update.isFinal {
                    self.finalizeDictationUI()
                }
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.finalizeDictationUI()
                self.presentDictationError(error)
            }
        )
    }

    /// Toggle off — user clicked dictate again or pressed Escape. The
    /// recogniser will produce one final result with the cleaned-up
    /// transcript shortly after; we let `onUpdate(isFinal:)` handle
    /// the UI cleanup so the field reflects the polished text.
    private func stopDictation() {
        WalkerCharacter.playSelectionSound()
        dictationManager.stop()
        // If no final update arrives within a beat (e.g. mic stopped
        // mid-silence with no recognised speech), reset the UI anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isDictating else { return }
            self.finalizeDictationUI()
        }
    }

    private func finalizeDictationUI() {
        guard isDictating else { return }
        isDictating = false
        applyIdleButtonStyle()
        // Refocus the input so the user can hit Enter or keep typing
        // without an extra click.
        window?.makeFirstResponder(inputField)
    }

    private func applyDictatingButtonStyle() {
        let t = theme
        dictateButton.layer?.backgroundColor = t.accentColor.withAlphaComponent(0.22).cgColor
        dictateButton.normalBg = t.accentColor.withAlphaComponent(0.22).cgColor
        dictateButton.hoverBg = t.accentColor.withAlphaComponent(0.34).cgColor
        dictateButton.contentTintColor = t.accentColor
        dictateButton.toolTip = "Stop dictation"
        if let img = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop dictation") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            dictateButton.image = img.withSymbolConfiguration(config)
        }
    }

    private func applyIdleButtonStyle() {
        let t = theme
        dictateButton.layer?.backgroundColor = t.separatorColor.withAlphaComponent(0.14).cgColor
        dictateButton.normalBg = t.separatorColor.withAlphaComponent(0.14).cgColor
        dictateButton.hoverBg = t.separatorColor.withAlphaComponent(0.28).cgColor
        dictateButton.contentTintColor = t.textDim
        dictateButton.toolTip = "Dictate message"
        if let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictate message") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            dictateButton.image = img.withSymbolConfiguration(config)
        }
    }

    private func presentDictationError(_ error: DictationManager.DictationError) {
        let alert = NSAlert()
        alert.messageText = "Dictation unavailable"
        alert.informativeText = error.errorDescription ?? "Couldn't start dictation."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }
        alert.runModal()
    }
}

import AppKit

extension TerminalView {
    var welcomeSuggestionPool: [(String, String, String)] {
        // Orion is single-persona with no archive switcher — always the
        // starter-pack pool.
        WelcomeChipsView.starterPackSuggestionPool
    }

    func ensureWelcomeSuggestionSelection(forceRefresh: Bool = false) {
        guard forceRefresh || currentWelcomeSuggestions.isEmpty else {
            return
        }

        currentWelcomeSuggestions = Array(welcomeSuggestionPool.shuffled().prefix(4))
    }

    var shouldShowStarterPackUpsell: Bool {
        // Orion has no archive — the Starter Pack / LennyData
        // upsell is permanently disabled. Always false.
        false
    }

    var shouldPresentStarterPackWelcomeBanner: Bool {
        shouldShowStarterPackUpsell && !starterPackWelcomeBannerDismissed
    }

    var welcomeSuggestions: [(String, String, String)] {
        ensureWelcomeSuggestionSelection()
        return currentWelcomeSuggestions
    }

    func openOfficialMCPURL() {
        NSWorkspace.shared.open(officialMCPURL)
    }

    func completeOfficialMCPSetupFlow() {
        isShowingOfficialMCPSetupPanel = false
        starterPackWelcomeBannerDismissed = true
        showWelcomeSuggestionsPanel()
    }

    func showOfficialMCPSetupPanel() {
        // Orion: the lennysdata.com auth-key card is permanently disabled.
        // Orbit content is free; Orion should never block the user behind
        // an auth prompt for an upstream service it doesn't even use.
        isShowingOfficialMCPSetupPanel = false
    }

    func openAppSettings() {
        NSApp.sendAction(#selector(AppDelegate.openSettings), to: NSApp.delegate, from: self)
    }

    func showWelcomeSuggestionsPanel() {
        expertSuggestionStack.arrangedSubviews.forEach { view in
            expertSuggestionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if requiresInitialConnectionSetup {
            let setupCard = ConnectionSetupCardView(theme: theme)
            setupCard.onOpenSettings = { [weak self] in
                self?.openAppSettings()
            }
            expertSuggestionLabel.isHidden = true
            expertSuggestionStack.addArrangedSubview(setupCard)
            setupCard.widthAnchor.constraint(equalTo: expertSuggestionStack.widthAnchor).isActive = true
            welcomeChipsView = nil
            expertSuggestionContainer.isHidden = false
            expertSuggestionContainer.alphaValue = 1
            relayoutPanels()
            return
        }

        // Orion: the official-Lenny-MCP / archive-token setup flow was
        // removed with the archive subsystem. Orion never blocks behind an
        // MCP auth prompt, so we go straight to the business-context nudge
        // and the welcome chips.

        // First-launch (or post-version-bump-with-empty-context) survey
        // nudge. Lives above the chips so users see it the first time
        // they open the popover. Skip stamps the current version so it
        // doesn't reappear until the next update.
        if AppSettings.shouldPromptForBusinessContext, !businessContextPromptDismissedThisSession {
            let card = BusinessContextPromptCardView(theme: theme)
            card.onSetupTapped = { [weak self] in
                guard let self else { return }
                // Open Settings first so the SwiftUI view is mounted
                // and its .onReceive subscriber is registered. Then
                // post the pane-switch on the next runloop tick — if
                // we post first, a freshly-constructed view misses
                // the notification.
                self.openAppSettings()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .liLJustinOpenSettingsPane,
                        object: SettingsPane.businessContext.rawValue
                    )
                }
            }
            card.onSkipTapped = { [weak self] in
                guard let self else { return }
                AppSettings.markBusinessContextPromptShown()
                self.businessContextPromptDismissedThisSession = true
                self.showWelcomeSuggestionsPanel()
            }
            expertSuggestionLabel.isHidden = true
            expertSuggestionStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: expertSuggestionStack.widthAnchor).isActive = true
            welcomeChipsView = nil
            expertSuggestionContainer.isHidden = false
            expertSuggestionContainer.alphaValue = 1
            relayoutPanels()
            return
        }

        if shouldPresentStarterPackWelcomeBanner {
            let upsell = StarterPackUpsellCardView(theme: theme, compact: true, showsSkipButton: true)
            upsell.onConnectTapped = { [weak self] in
                self?.showOfficialMCPSetupPanel()
            }
            upsell.onSkipTapped = { [weak self] in
                self?.starterPackWelcomeBannerDismissed = true
                self?.showWelcomeSuggestionsPanel()
            }
            expertSuggestionLabel.isHidden = true
            expertSuggestionStack.addArrangedSubview(upsell)
            upsell.widthAnchor.constraint(equalTo: expertSuggestionStack.widthAnchor).isActive = true
            welcomeChipsView = nil
            expertSuggestionContainer.isHidden = false
            expertSuggestionContainer.alphaValue = 1
            relayoutPanels()
            return
        }

        let chips = WelcomeChipsView(
            theme: theme,
            suggestions: welcomeSuggestions
        )
        chips.onChipTapped = { [weak self] text in
            guard let self else { return }
            self.hideWelcomeSuggestionsPanel()
            self.inputField.stringValue = text
            self.inputSubmitted()
        }

        expertSuggestionLabel.isHidden = true
        expertSuggestionStack.addArrangedSubview(chips)
        chips.widthAnchor.constraint(equalTo: expertSuggestionStack.widthAnchor).isActive = true

        welcomeChipsView = chips
        expertSuggestionContainer.isHidden = false
        expertSuggestionContainer.alphaValue = 1
        relayoutPanels()
    }

    func firstRunConfigurationSignature() -> String {
        [
            "transport:\(AppSettings.preferredTransport.rawValue)",
            "openai:\(AppSettings.openAIAPIKey != nil ? "1" : "0")",
            "setup:\(requiresInitialConnectionSetup ? "1" : "0")",
            "bizctx:\(AppSettings.businessContext != nil ? "1" : "0")",
            "bizctx-prompt:\(AppSettings.shouldPromptForBusinessContext ? "1" : "0")"
        ].joined(separator: "|")
    }

    func refreshFirstRunStateIfNeeded(forceRefresh: Bool = false) {
        let signature = firstRunConfigurationSignature()
        guard forceRefresh || lastObservedFirstRunConfigurationSignature != signature else { return }

        lastObservedFirstRunConfigurationSignature = signature
        starterPackWelcomeBannerDismissed = false
        currentWelcomeSuggestions = []
        lastRenderedWelcomeSignature = nil

        guard isShowingInitialWelcomeState, !isExpertMode else { return }

        if requiresInitialConnectionSetup {
            onRefreshSetupState?()
            return
        }

        showWelcomeGreeting(forceRefresh: true)
    }

    func refreshWelcomePreviewIfNeeded() {
        refreshFirstRunStateIfNeeded()
    }

    func hideWelcomeSuggestionsPanel() {
        expertSuggestionStack.arrangedSubviews.forEach { view in
            expertSuggestionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        welcomeChipsView = nil
        expertSuggestionContainer.isHidden = true
        expertSuggestionContainer.alphaValue = 0
        relayoutPanels()
    }
}

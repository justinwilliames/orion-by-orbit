import AppKit

extension TerminalView {
    func welcomeSuggestionPool(for archiveMode: AppSettings.ArchiveAccessMode) -> [(String, String, String)] {
        archiveMode == .starterPack
            ? WelcomeChipsView.starterPackSuggestionPool
            : WelcomeChipsView.defaultSuggestionPool
    }

    func ensureWelcomeSuggestionSelection(forceRefresh: Bool = false) {
        let archiveMode = welcomePreviewArchiveMode
        guard forceRefresh || currentWelcomeArchiveMode != archiveMode || currentWelcomeSuggestions.isEmpty else {
            return
        }

        currentWelcomeArchiveMode = archiveMode
        currentWelcomeSuggestions = Array(welcomeSuggestionPool(for: archiveMode).shuffled().prefix(4))
    }

    var welcomePreviewMode: AppSettings.WelcomePreviewMode {
        AppSettings.welcomePreviewMode
    }

    var welcomePreviewArchiveMode: AppSettings.ArchiveAccessMode {
        switch welcomePreviewMode {
        case .live:
            return AppSettings.effectiveArchiveAccessMode
        case .starterPackWithBanner, .starterPackConnected:
            return .starterPack
        case .officialConnected:
            return .officialMCP
        }
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
        AppSettings.mcpReconnectNeeded = false
        isShowingOfficialMCPSetupPanel = false
        starterPackWelcomeBannerDismissed = true
        currentWelcomeArchiveMode = nil
        showWelcomeSuggestionsPanel()
    }

    func showOfficialMCPSetupPanel() {
        // Orion: the lennysdata.com auth-key card is permanently disabled.
        // Orbit content is free; Orion should never block the user behind
        // an auth prompt for an upstream service it doesn't even use.
        AppSettings.mcpReconnectNeeded = false
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

        // MCP reconnect: persisted failure flag from a previous turn.
        // Proactive: token-based path selected but no token saved yet (first-run / unconfigured).
        // Native MCP (codex mcp add / codex mcp login) is self-sufficient — no app token needed.
        let hasNativeMCPConfig = AppSettings.detectedOfficialMCPSources.contains(.claudeGlobalConfig)
            || AppSettings.detectedOfficialMCPSources.contains(.codexGlobalConfig)
        let hasWorkingToken = AppSettings.officialLennyMCPToken != nil
            || AppSettings.shellEnvironmentOfficialMCPToken() != nil
        let needsTokenSetup = !hasNativeMCPConfig
            && AppSettings.effectiveArchiveAccessMode == .officialMCP
            && !hasWorkingToken
            && !mcpSetupBannerDismissedThisSession
        let shouldPromptMCPSetup = AppSettings.mcpReconnectNeeded
            || isShowingOfficialMCPSetupPanel
            || needsTokenSetup

        if shouldPromptMCPSetup {
            showOfficialMCPSetupPanel()
            return
        }

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
            "welcome:\(welcomePreviewMode.rawValue)",
            "archive:\(AppSettings.archiveAccessMode.rawValue)",
            "transport:\(AppSettings.preferredTransport.rawValue)",
            "official:\(AppSettings.hasDetectedOfficialMCPConfiguration ? "1" : "0")",
            "token:\(AppSettings.officialLennyMCPToken != nil ? "1" : "0")",
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
        currentWelcomeArchiveMode = nil
        currentWelcomeSuggestions = []
        lastRenderedWelcomeSignature = nil
        lastObservedWelcomePreviewMode = welcomePreviewMode

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

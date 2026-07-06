import AppKit

extension WalkerCharacter {
    // PHASE 2 / Lenny-removal — the floating "Ask <Expert>" name tag was a
    // sprite decoration (a borderless window pinned above the walking
    // character's head). The visible sprite is gone and the guest-expert
    // subsystem was removed, so the tag has nothing to anchor and no
    // purpose. These are inert no-ops retained so the many call sites in the
    // kept chat/session code keep resolving without edits. Relocated here
    // from the deleted WalkerCharacterExpertTag.swift; `expertNameWindow` is
    // never created, so both are cheap.
    func updateExpertNameTag() {
        // No-op: the sprite name-tag window is gone.
    }

    func hideExpertNameTag() {
        if expertNameWindow?.isVisible ?? false {
            expertNameWindow?.orderOut(nil)
        }
    }

    func setup() {
        // PHASE 2 — the visible walking sprite has been removed. Orion is
        // now a HEADLESS chat host: the chat popover is summoned from the
        // menubar status item (see ChatPopoverController) and the sprite's
        // floating GIF window no longer exists.
        //
        // We still create `window` — a 1×1, fully transparent, off-screen,
        // mouse-ignoring, NEVER-ordered-front NSWindow — purely so the many
        // `window.frame` / `window.level` / `window.isVisible` reads that
        // remain in the (now largely inert) sprite code paths keep
        // resolving and the build stays green. It is never shown, so the
        // user sees nothing. Removing the property outright would mean
        // editing dozens of call sites for zero functional gain.
        let contentRect = CGRect(x: -10_000, y: -10_000, width: 1, height: 1)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // Deliberately NOT ordered front — the sprite is gone.
    }

    func handleClick() {
        if isCompanionAvatar, let representedExpert {
            focusedExpert = representedExpert
            claudeSession?.focusedExpert = representedExpert
            if isIdleForPopover {
                closePopover()
            } else {
                openPopover()
            }
            return
        }
        if isOnboarding {
            openOnboardingPopover()
            return
        }
        if isIdleForPopover {
            isPopoverPinned = false
            syncPopoverPinState()
            closePopover()
        } else {
            openPopover()
        }
    }

    func setMovementLocked(_ locked: Bool) {
        movementLocked = locked
        if locked {
            isWalking = false
            isPaused = true
            pauseEndTime = .greatestFiniteMagnitude
            setFacing(.front)
        } else if !isIdleForPopover && !isDraggingHorizontally {
            pauseEndTime = CACurrentMediaTime() + Double.random(in: 1.5...3.5)
        }
    }

    // PHASE 2 — sprite drag removed. The visible character is gone, so
    // CharacterContentView (which used to forward mouse drags here) is no
    // longer attached to any on-screen window. These methods are retained
    // as inert no-ops so the (dead) call sites still resolve; they perform
    // no window movement and touch no removed sprite machinery.
    func beginHorizontalDrag(at event: NSEvent) {}
    func continueHorizontalDrag(with event: NSEvent) {}
    func endHorizontalDrag() {
        isDraggingHorizontally = false
        usesExpandedHorizontalRange = false
    }
    func cancelHorizontalDrag() {
        dropTimer?.invalidate()
        dropTimer = nil
        isDraggingHorizontally = false
        usesExpandedHorizontalRange = false
    }

    func configureCompanionAvatar(expert: ResponderExpert, position: CGFloat) {
        representedExpert = expert
        isCompanionAvatar = true
        focusedExpert = nil
        isOnboarding = false
        isIdleForPopover = false
        isWalking = false
        isPaused = true
        pauseEndTime = .greatestFiniteMagnitude
        positionProgress = position
        hideBubble()
        setPersona(.expert(expert))
        updateCharacterTooltip()
        updateExpertNameTag()
        window.orderFrontRegardless()
    }

    func hideCompanionAvatar() {
        representedExpert = nil
        isCompanionAvatar = false
        updateCharacterTooltip()
        hideBubble()
        hideExpertNameTag()
        window.orderOut(nil)
    }

    func focus(on expert: ResponderExpert?) {
        let wasExpertMode = focusedExpert != nil
        focusedExpert = expert
        claudeSession?.focusedExpert = expert
        if let expert {
            isWalking = false
            isPaused = true
            pauseEndTime = .greatestFiniteMagnitude
            setFacing(.front)
            setPersona(.expert(expert))
        } else {
            setPersona(.orion)
            if wasExpertMode, !movementLocked, !isDraggingHorizontally, !isOnboarding {
                isPaused = true
                isWalking = false
                pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.6...1.4)
            }
        }
        updateCharacterTooltip()
        updateExpertNameTag()
        refreshPopoverHeader()
        if !isIdleForPopover {
            openPopover()
        } else {
            restoreTranscriptState()
        }
    }

    func restoreTranscriptState() {
        updateInputPlaceholder()
        terminalView?.setReturnToLennyVisible(focusedExpert != nil)
        terminalView?.isExpertMode = focusedExpert != nil

        guard let session = claudeSession, let terminalView else { return }
        let activeHistory = session.history(for: focusedExpert)
        let conversationKey = session.key(for: focusedExpert)
        let lastReadHistoryCount = session.lastReadHistoryCount(for: focusedExpert)

        if let expert = focusedExpert {
            if activeHistory.isEmpty {
                terminalView.renderedConversationKey = conversationKey
                terminalView.showExpertGreeting(for: expert)
                if session.isBusy, !currentActivityStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    terminalView.setLiveStatus(
                        currentActivityStatus,
                        isBusy: true,
                        isError: false,
                        experts: [expert]
                    )
                } else {
                    terminalView.clearTranscriptLiveStatus()
                }
                terminalView.hideExpertSuggestions(clearState: false)
                return
            }

            terminalView.replayConversation(
                activeHistory,
                expertSuggestions: session.expertSuggestionEntries(for: expert),
                restoreStrategy: .focusUnreadBoundary(lastReadHistoryCount: lastReadHistoryCount)
            )
            terminalView.renderedConversationKey = conversationKey
            if session.isBusy, !currentActivityStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalView.setLiveStatus(
                    currentActivityStatus,
                    isBusy: true,
                    isError: false,
                    experts: [expert]
                )
            } else {
                terminalView.clearTranscriptLiveStatus()
            }
            terminalView.hideExpertSuggestions(clearState: false)
            return
        }

        if activeHistory.isEmpty {
            terminalView.renderedConversationKey = conversationKey
            terminalView.showWelcomeGreeting()
            if session.isBusy, !currentActivityStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalView.setLiveStatus(
                    currentActivityStatus,
                    isBusy: true,
                    isError: false,
                    experts: session.livePresenceExperts
                )
            } else {
                terminalView.clearTranscriptLiveStatus()
            }
            terminalView.hideExpertSuggestions()
            return
        }

        terminalView.replayConversation(
            activeHistory,
            expertSuggestions: session.expertSuggestionEntries(for: nil),
            restoreStrategy: .focusUnreadBoundary(lastReadHistoryCount: lastReadHistoryCount)
        )
        terminalView.renderedConversationKey = conversationKey

        if session.isBusy, !currentActivityStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            terminalView.setLiveStatus(
                currentActivityStatus,
                isBusy: true,
                isError: false,
                experts: session.livePresenceExperts
            )
        } else {
            terminalView.clearTranscriptLiveStatus()
        }

        let persistedEntries = session.expertSuggestionEntries(for: nil)
        guard persistedEntries.isEmpty else {
            terminalView.hideExpertSuggestions(clearState: false)
            return
        }

        let controllerSuggestions = controller?.suggestedExperts ?? []
        let suggestions = controllerSuggestions.isEmpty
            ? terminalView.currentExpertSuggestions
            : controllerSuggestions
        if suggestions.isEmpty {
            terminalView.hideExpertSuggestions()
        } else {
            terminalView.setExpertSuggestionsCollapsed(suggestions)
        }
    }

    private func loadDirectionalImages() {
        // PHASE 2 — the sprite GIF assets (CharacterSprites) were removed
        // along with the visible character. Nothing renders them, so this
        // is now a no-op rather than loading bitmaps that don't exist.
    }

    func setFacing(_ facing: WalkerFacing) {
        // Sleep state owns the image. Any code path that tries to swap
        // facing while Orion is asleep — drag, persona swap, expert
        // focus, mid-pause idle facing reroll, walk-cycle pause entry —
        // is silently ignored. Without this guard the sleep GIF would
        // flicker briefly to a directional image whenever any of those
        // paths fired during a nap, producing the "flicker from sleeping
        // to standing to sleeping" Sir reported. The actual sleep / wake
        // transition still routes through enterSleep() / wakeUp() which
        // own image swapping during state changes.
        guard !isSleeping else { return }
        imageView?.image = directionalImages[facing] ?? directionalImages[.front]
    }

    private func setPersona(_ persona: WalkerPersona) {
        let previousPersona = self.persona
        self.persona = persona

        switch persona {
        case .orion:
            loadDirectionalImages()
            characterColor = NSColor(red: 0.96, green: 0.63, blue: 0.23, alpha: 1.0)

        case .expert(let expert):
            let avatar = loadExpertAvatar(at: expert.avatarPath)
            directionalImages[.front] = avatar
            directionalImages[.left] = avatar
            directionalImages[.right] = avatar
            directionalImages[.back] = avatar
            characterColor = .white
        }

        setFacing(.front)
            animatePersonaSwap()
        if let terminalView {
            terminalView.characterColor = characterColor
        }
        playHandoffEffect(from: previousPersona, to: persona)
    }

    private func updateCharacterTooltip() {
        let tooltip: String
        if let expert = focusedExpert ?? representedExpert {
            tooltip = "Ask \(expert.name)"
        } else {
            tooltip = "Ask Orbit"
        }
        window.contentView?.toolTip = tooltip
    }

    private func loadExpertAvatar(at path: String) -> NSImage {
        NSImage(contentsOfFile: path) ?? NSImage(size: NSSize(width: displayWidth, height: displayHeight))
    }
}

// MARK: - Sleep state machine
// After ~1.5–4 minutes of no interaction Orion curls up for a 30–120s
// nap (`main-sleeping.gif`). Any click / popover open wakes him; otherwise
// he wakes on his own and paces again. Cadence is randomised so the
// rhythm doesn't feel scripted. State vars + tunables live on
// WalkerCharacter (see WalkerCharacter.swift).
extension WalkerCharacter {

    /// Bump the last-interaction timestamp, re-randomise the next
    /// idle-before-sleep threshold, and wake Orion if he was asleep.
    /// Call from any code path representing real user interaction
    /// (click on the sprite, popover open, drag, message sent).
    func noteUserInteraction() {
        lastInteractionAt = CACurrentMediaTime()
        idleSleepThreshold = TimeInterval.random(
            in: WalkerCharacter.minIdleBeforeSleep...WalkerCharacter.maxIdleBeforeSleep
        )
        if isSleeping { wakeUp() }
    }

    /// Curl up. Stops walking, displays the sleeping GIF, sets a wake
    /// time 30–120s out at random.
    func enterSleep() {
        guard !isSleeping else { return }
        isSleeping = true
        isWalking = false
        isPaused = true
        wakeAt = CACurrentMediaTime() + TimeInterval.random(
            in: WalkerCharacter.minSleepDuration...WalkerCharacter.maxSleepDuration
        )
        if let img = sleepingImage { imageView?.image = img }
        // Hide any active status / completion bubble while asleep —
        // looks weird with a bubble hovering over a sleeping character.
        // Exception: when an external producer (Pomodoro) is driving
        // the bubble surface, keep the bubble visible (e.g. the green
        // break-countdown should remain readable while Orion naps).
        if !pomodoroBubbleHold {
            hideBubble()
        }
    }

    /// Get up. Returns to the front-facing idle pose, takes a brief
    /// 1–3s pause, then the existing pause→walk loop kicks back in.
    ///
    /// CRITICAL: must reset `lastInteractionAt` to "now". Without this,
    /// `updateSleepState` on the next tick computes `idleFor` against
    /// the stale pre-sleep timestamp, instantly trips the threshold,
    /// and sends him straight back to sleep — a frame after waking.
    /// That bug is what made Sir feel like he was asleep "a really
    /// long time" — natural wakes were near-zero awake windows.
    ///
    /// Also schedules an ambient bubble shortly after waking so the
    /// transition feels like "stretches, looks around, says
    /// something" rather than a silent re-pace until the cadence
    /// timer next fires.
    func wakeUp() {
        guard isSleeping else { return }
        let now = CACurrentMediaTime()
        isSleeping = false
        isWalking = false
        isPaused = true
        pauseEndTime = now + TimeInterval.random(in: 1.0...3.0)
        lastInteractionAt = now
        idleSleepThreshold = TimeInterval.random(
            in: WalkerCharacter.minIdleBeforeSleep...WalkerCharacter.maxIdleBeforeSleep
        )
        // Pull the next ambient bubble forward so a fresh wake produces
        // a "morning hello" within 8–25s rather than waiting out the
        // full 90–240s cadence. Caps Sir's perception of "he never
        // says anything" without reducing the cadence in the steady
        // state. Skips if a bubble is already queued sooner than that.
        let postWakeBubbleAt = now + TimeInterval.random(in: 8.0...25.0)
        if nextAmbientBubbleAt > postWakeBubbleAt {
            nextAmbientBubbleAt = postWakeBubbleAt
        }
        setFacing(.front)
    }

    /// Per-tick check — returns true if currently asleep so the caller
    /// skips movement updates and holds position. Called from update().
    ///
    /// Sleep can only fire on TRUE inactivity. Block whenever:
    /// - the popover is open (active conversation)
    /// - the model is mid-turn (`isClaudeBusy`) — a long answer is
    ///   streaming back and Sir is reading or about to read it
    /// - the character is on screen as a focused expert / companion
    /// - the character is mid-walk (would look weird snapping to sleep)
    func updateSleepState() -> Bool {
        let now = CACurrentMediaTime()
        if isSleeping {
            // Defensive image reassertion. The setFacing() guard above
            // catches the common cases, but the runtime is full of
            // animation/persona-swap paths that touch imageView.image
            // through other routes. Reassign only when the image differs
            // (using === reference comparison) so we don't re-trigger
            // the GIF playback from frame 0 on every tick — that would
            // freeze the sleeping animation visually.
            if let sleepingImage, imageView?.image !== sleepingImage {
                imageView?.image = sleepingImage
            }
            // While sleeping, an in-flight model turn or open popover
            // should also wake Orion immediately so he's not napping
            // through someone trying to talk to him.
            if isClaudeBusy || isIdleForPopover {
                wakeUp()
                return false
            }
            if now >= wakeAt && !pomodoroForceAsleep {
                wakeUp()
                return false
            }
            return true
        }
        let idleFor = now - lastInteractionAt
        if idleFor >= idleSleepThreshold,
           !isWalking,
           !isIdleForPopover,
           !isClaudeBusy,
           !pomodoroForceAwake,
           focusedExpert == nil,
           !isCompanionAvatar {
            enterSleep()
            return true
        }
        return false
    }
}

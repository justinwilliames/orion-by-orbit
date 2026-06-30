import AppKit

extension WalkerCharacter {
    func openOnboardingPopover() {
        showingCompletion = false
        hideBubble()

        isIdleForPopover = true
        isWalking = false
        isPaused = true
        setFacing(.front)

        if popoverWindow == nil {
            createPopoverWindow()
        }

        terminalView?.inputField.isEditable = false
        terminalView?.updatePlaceholder("")

        // Reset transcript to a clean state on each call so repeated clicks don't accumulate content
        if let tv = terminalView {
            tv.currentAssistantText = ""
            let views = tv.transcriptStack.arrangedSubviews
            views.forEach { view in
                tv.transcriptStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        let welcome = """
        Orion — Orbit's menu-bar lifecycle assistant.

        Ask about lifecycle, deliverability, Braze, retention. The Orbit playbook, in your menu bar.
        """
        terminalView?.appendStreamingText(welcome)
        terminalView?.endStreaming()

        updatePopoverPosition()
        popoverWindow?.orderFrontRegardless()
        syncPopoverPinState()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.closeOnboarding()
        }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.closeOnboarding(); return nil }
            return event
        }
    }

    private func closeOnboarding() {
        removeEventMonitors()
        expertSwitcherPopover?.close()
        popoverWindow?.orderOut(nil)
        popoverWindow = nil
        terminalView = nil
        isIdleForPopover = false
        isOnboarding = false
        isPaused = true
        pauseEndTime = CACurrentMediaTime() + Double.random(in: 1.0...3.0)
        setFacing(.front)
        controller?.completeOnboarding()
    }

    func openPopover() {
        // Capture any visible ambient line BEFORE noteUserInteraction
        // → hideBubble runs and clears it. If Sir clicks Orion
        // while a tip / quote / observation is on screen, that text
        // becomes the seed prompt for the new chat — turning the
        // passing remark into a thread he can drill into.
        let drillInSeed = currentAmbientLineText

        // Real user interaction → wake from sleep + reset idle timer.
        noteUserInteraction()

        if let siblings = controller?.characters {
            for sibling in siblings where sibling !== self && sibling.isIdleForPopover {
                if sibling.isPopoverPinned { continue }
                sibling.closePopover()
            }
        }

        isIdleForPopover = true
        isWalking = false
        isPaused = true
        setFacing(.front)

        showingCompletion = false
        hideBubble()

        if popoverWindow == nil {
            createPopoverWindow()
        }

        // Reshuffle the welcome chips on every popover open. The pool is
        // 1:1 with the Orbit guide library; 4 are shown at a time, drawn
        // at random so the user sees fresh prompts each time.
        terminalView?.currentWelcomeSuggestions = []
        terminalView?.lastRenderedWelcomeSignature = nil

        if claudeSession == nil {
            let session = ClaudeSession()
            session.focusedExpert = focusedExpert
            claudeSession = session
            wireSession(session)
            session.start()
        } else if claudeSession?.isRunning != true {
            claudeSession?.focusedExpert = focusedExpert
            claudeSession?.start()
        }

        refreshPopoverHeader()
        restoreTranscriptState()

        updatePopoverPosition()
        // After the new-chat close-and-reopen cycle, orderFrontRegardless +
        // makeKey didn't reliably leave the window key — keystrokes hit the
        // popover but Enter never fired the input field's action because
        // Orion (an LSUIElement app) wasn't the active app. Activating
        // explicitly + using makeKeyAndOrderFront makes the popover the
        // single point of focus regardless of whether we're opening fresh
        // or coming through a close-and-reopen.
        NSApp.activate(ignoringOtherApps: true)
        popoverWindow?.makeKeyAndOrderFront(nil)
        syncPopoverPinState()

        // makeFirstResponder runs on the next tick so the window's
        // key-window transition has time to commit before we install
        // the input field as first responder. Without the delay, the
        // responder assignment can race the activation and leave focus
        // on whatever was previously responder (a chip button, the
        // close button) — which is what the new-chat "Enter does
        // nothing" symptom reduces to.
        if let terminal = terminalView {
            DispatchQueue.main.async { [weak self] in
                self?.popoverWindow?.makeFirstResponder(terminal.inputField)
            }
        }

        refreshPopoverEventMonitors()

        // Drill-in: if Sir clicked while an ambient bubble was showing,
        // seed the chat with a "tell me more" prompt referencing the
        // line he just saw and send it. Skipped on a session that
        // already has history (he might be reopening a paused chat,
        // not following up on a tip). Skipped if the ambient line is
        // suspiciously short to be useful as context.
        if let seed = drillInSeed,
           seed.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8,
           let session = claudeSession,
           session.history(for: focusedExpert).isEmpty,
           let terminal = terminalView {
            let prompt = "Tell me more about this — who said it, the topic behind it, or how to think about it: \(seed)"
            // Tiny delay so the welcome state finishes rendering and
            // the input field is the first responder before the
            // synthesised submit fires. Without it the inputSubmitted
            // sometimes runs before showWelcomeGreeting wipes its own
            // welcome panel, leaving a stale chip grid behind the
            // user's question.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self, weak terminal] in
                guard let terminal else { return }
                _ = self
                terminal.inputField.stringValue = prompt
                terminal.inputSubmitted()
            }
        }
    }

    @objc func expandToggleTapped() {
        // Same activeScreen treatment as updatePopoverPosition — the
        // expand-toggle's height calculation reads visibleFrame, which
        // is screen-specific. Using NSScreen.main would size against
        // whichever monitor has the focused window, not the Dock screen.
        guard let popover = popoverWindow, let screen = controller?.activeScreen ?? NSScreen.main else { return }
        isPopoverExpanded = !isPopoverExpanded

        let charFrame = window.frame
        let visibleFrame = screen.visibleFrame

        // ── New width ───────────────────────────────────────────────
        // 50% wider on expand. Falls back to the EXACT default width
        // when collapsing — Sir flagged that "shrink should go back to
        // the original size" after v0.1.45 left it at intermediate
        // dimensions.
        let baseWidth = WalkerCharacter.defaultPopoverWidth
        let expandedWidth = min(baseWidth * 1.5, visibleFrame.width - 8)
        let newWidth: CGFloat = isPopoverExpanded ? expandedWidth : baseWidth

        // ── New height ──────────────────────────────────────────────
        let newHeight: CGFloat
        if isPopoverExpanded {
            let popoverBottomY = charFrame.maxY - 10
            let maxAvailable = visibleFrame.maxY - 4 - popoverBottomY
            newHeight = min(max(maxAvailable, 500), visibleFrame.height - 20)
        } else {
            newHeight = WalkerCharacter.defaultPopoverHeight
        }

        // ── New origin — recompute from scratch using the new size ──
        // so collapse always anchors the popover bottom at the
        // character's head, regardless of where it sat when expanded.
        let desiredBottomY = charFrame.maxY - 10
        let clampedBottomY = max(
            visibleFrame.minY + 4,
            min(desiredBottomY, visibleFrame.maxY - newHeight - 4)
        )
        var newX = charFrame.midX - newWidth / 2
        newX = max(visibleFrame.minX + 4, min(newX, visibleFrame.maxX - newWidth - 4))

        let newFrame = NSRect(x: newX, y: clampedBottomY, width: newWidth, height: newHeight)

        // Pre-compute the tail X relative to the NEW frame, not the
        // current one. The animator hasn't applied yet, so reading
        // popover.frame.minX would give the OLD frame and the tail
        // would morph to the wrong horizontal position by the time
        // the animation lands.
        let newTailCenterX = charFrame.midX - newX

        // Animate the window frame AND the bubble shell path together
        // so the speech-bubble outline stays in sync with the content
        // throughout the resize. Use NSWindow's native animated
        // setFrame rather than the animator proxy — the proxy was
        // unreliable on shrink (popover wouldn't always reach the
        // target size). The native API handles both directions
        // deterministically.
        rebuildPopoverBubbleShellPath(
            forSize: newFrame.size,
            tailCenterX: newTailCenterX,
            animated: true,
            duration: 0.28
        )
        popover.setFrame(newFrame, display: true, animate: true)

        let symbolName = isPopoverExpanded
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            popoverExpandButton?.image = img.withSymbolConfiguration(config)
        }
    }

    /// Rebuild the speech-bubble outline path to match a new window
    /// size. Must be called whenever the popover frame changes —
    /// without this, the `CAShapeLayer` keeps the path it was given
    /// at creation, the bubble outline stays the original size, and
    /// any new content stretches outside the drawn outline (the
    /// "detached title" bug).
    ///
    /// When `animated` is true the path change is wrapped in a
    /// `CABasicAnimation` so the outline morphs alongside the window
    /// frame animation rather than snapping to the new shape on
    /// frame 0.
    func rebuildPopoverBubbleShellPath(
        forSize size: CGSize,
        tailCenterX explicitTailX: CGFloat? = nil,
        animated: Bool,
        duration: CFTimeInterval = 0.28
    ) {
        guard let bubbleShape = popoverBubbleShape else { return }

        // When the caller knows what tail X the path should land on
        // (e.g. during expandToggleTapped, where the popover frame is
        // mid-animation and `popover.frame.minX` would lag), it can
        // pass the value explicitly. Otherwise fall back to reading
        // the current popover position.
        let tailX = explicitTailX ?? tailCenterXRelativeToPopover()

        let newPath = WalkerCharacter.bubbleShellPath(
            size: size,
            tailHeight: WalkerCharacter.popoverTailHeight,
            tailWidth: WalkerCharacter.popoverTailWidth,
            cornerRadius: 18,
            tailCenterX: tailX
        )

        if animated {
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = bubbleShape.path
            anim.toValue = newPath
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bubbleShape.add(anim, forKey: "pathResize")
        }
        bubbleShape.frame = CGRect(origin: .zero, size: size)
        bubbleShape.path = newPath
    }

    func closePopover() {
        guard isIdleForPopover else { return }

        expertSwitcherPopover?.close()
        isPopoverExpanded = false
        if let btn = popoverExpandButton,
           let img = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            btn.image = img.withSymbolConfiguration(config)
        }
        // Reset window to default size before hiding so the next
        // open starts collapsed. Both width and height reset — without
        // the width reset a popover that was expanded then closed
        // would reopen at the expanded width with no visual cue.
        if let popover = popoverWindow {
            let f = popover.frame
            let needsResize = f.width != WalkerCharacter.defaultPopoverWidth
                || f.height != WalkerCharacter.defaultPopoverHeight
            if needsResize {
                let resetSize = CGSize(
                    width: WalkerCharacter.defaultPopoverWidth,
                    height: WalkerCharacter.defaultPopoverHeight
                )
                let newFrame = NSRect(origin: f.origin, size: resetSize)
                popover.setFrame(newFrame, display: false)
                rebuildPopoverBubbleShellPath(forSize: resetSize, animated: false)
            }
        }

        popoverWindow?.orderOut(nil)
        removeEventMonitors()

        isIdleForPopover = false

        if showingCompletion {
            completionBubbleExpiry = CACurrentMediaTime() + 3.0
            showBubble(text: currentPhrase, isCompletion: true)
        } else if isClaudeBusy {
            if currentActivityStatus.isEmpty {
                currentPhrase = ""
                lastPhraseUpdate = 0
                updateThinkingPhrase()
                showBubble(text: currentPhrase, isCompletion: false)
            } else {
                hideBubble()
            }
        } else {
            setFacing(.front)
        }

        let delay = Double.random(in: 2.0...5.0)
        pauseEndTime = CACurrentMediaTime() + delay
    }

    @objc func togglePopoverPinned() {
        isPopoverPinned.toggle()
        syncPopoverPinState()
        refreshPopoverEventMonitors()
    }

    /// Clear the current conversation and reset the popover to the
    /// welcome state.
    ///
    /// v0.1.56 used a "nuclear" approach that nil'd out
    /// popoverWindow and terminalView immediately after orderOut.
    /// That crashed (NSStackView _removeView:animated: aborted)
    /// because orderOut is async — AppKit was still animating
    /// subview removal when we yanked the references out from
    /// under it. The stack view hit a dangling constraint to the
    /// already-released window's content view and SIGABRT'd. That
    /// also explained the "history and new conversation both
    /// showing" cosmetic — the teardown was incomplete, the new
    /// popover opened on top of the old transcript's residual
    /// state, and both layered briefly before the crash.
    ///
    /// v0.1.61 uses the canonical closePopover() path which does
    /// NOT nil window/terminal references — AppKit retains them
    /// through the animation and tears them down naturally. Then
    /// openPopover() on the next runloop tick re-renders cleanly.
    @objc func clearConversationTapped() {
        NSLog("[Orion] clearConversationTapped fired — close-and-reopen for clean reset")

        // Wipe the in-memory conversation BEFORE close so the
        // reopen's restoreTranscriptState reads an empty history.
        if let session = claudeSession {
            let key = session.key(for: focusedExpert)
            session.conversations[key] = nil
            session.pendingExperts.removeAll()
            session.assistantExplicitlyRequestedExperts = false
            session.livePresenceExperts = []
            session.liveToolCallsByID.removeAll()
            session.isBusy = false
        }

        // Use the canonical close path. closePopover does the right
        // thing: orderOut, removeEventMonitors, set isIdleForPopover
        // to false. It does NOT release popoverWindow or
        // terminalView — those stay valid so AppKit's animation
        // teardown completes safely.
        closePopover()

        // Re-open on the next runloop tick so the close commits
        // first. openPopover sees the existing popoverWindow and
        // reuses it; restoreTranscriptState reads the now-empty
        // session.history and renders the welcome state.
        DispatchQueue.main.async { [weak self] in
            self?.openPopover()
        }
    }

    @objc func closePopoverFromButton() {
        isPopoverPinned = false
        syncPopoverPinState()
        if isOnboarding {
            closeOnboarding()
            return
        }
        closePopover()
    }

    @objc func returnToGenieTapped() {
        controller?.returnToGenie()
    }

    func syncPopoverPinState() {
        if let pinButton = popoverPinButton {
            let symbolName = isPopoverPinned ? "pin.fill" : "pin"
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPopoverPinned ? "Unpin" : "Pin") {
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                pinButton.image = image.withSymbolConfiguration(config)
            }

            let t = resolvedTheme
            let normalBg = isPopoverPinned
                ? t.accentColor.withAlphaComponent(0.22).cgColor
                : t.separatorColor.withAlphaComponent(0.10).cgColor
            let hoverBg = isPopoverPinned
                ? t.accentColor.withAlphaComponent(0.32).cgColor
                : t.separatorColor.withAlphaComponent(0.22).cgColor
            pinButton.normalBg = normalBg
            pinButton.hoverBg = hoverBg
            pinButton.layer?.backgroundColor = normalBg
            pinButton.contentTintColor = isPopoverPinned ? t.accentColor : t.textDim
        }

        terminalView?.isPinnedOpen = isPopoverPinned
    }

    func refreshPopoverEventMonitors() {
        removeEventMonitors()
        guard isIdleForPopover, !isPopoverPinned else { return }

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let popover = self.popoverWindow else { return }
            let popoverFrame = popover.frame
            let charFrame = self.window.frame
            let switcherFrame = self.expertSwitcherPopover?.contentViewController?.view.window?.frame
            let isInsideSwitcher = switcherFrame?.contains(NSEvent.mouseLocation) == true
            if !popoverFrame.contains(NSEvent.mouseLocation) &&
                !charFrame.contains(NSEvent.mouseLocation) &&
                !isInsideSwitcher {
                self.closePopover()
            }
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.expertSwitcherPopover?.isShown == true {
                    self?.expertSwitcherPopover?.performClose(nil)
                    return nil
                }
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }

    func updateInputPlaceholder() {
        if let expert = focusedExpert {
            terminalView?.updatePlaceholder("Ask \(expert.name) a follow-up")
        } else {
            terminalView?.updatePlaceholder("Ask a question or drop in a file")
        }
    }
}

import AppKit

extension WalkerCharacter {
    func setup() {
        loadDirectionalImages()

        let screen = NSScreen.main!
        let dockTopY = screen.visibleFrame.origin.y
        let bottomPadding = displayHeight * 0.15
        let y = dockTopY - bottomPadding + yOffset

        let contentRect = CGRect(x: 0, y: y, width: displayWidth, height: displayHeight)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hostView = CharacterContentView(frame: CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight))
        hostView.character = self
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor

        let imageView = NSImageView(frame: hostView.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        // Anchor every pose to the bottom of the character window. Upright
        // GIFs (320×570 portrait) already fill the height so this is a
        // no-op for them. The sleeping GIF (522×292 landscape) would
        // otherwise centre-vertically and float above the Dock with empty
        // space below — bottom alignment plants it flush with the same
        // walking line as the upright sprites.
        imageView.imageAlignment = .alignBottom
        imageView.animates = true
        imageView.autoresizingMask = [.width, .height]
        hostView.addSubview(imageView)
        self.imageView = imageView
        setFacing(.front)

        window.contentView = hostView
        updateCharacterTooltip()
        window.orderFrontRegardless()
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

    func beginHorizontalDrag(at event: NSEvent) {
        // Picking him up counts as user interaction — wake him from
        // sleep before the rest of the drag logic runs, so the sprite
        // swaps to the front-facing GIF for the duration of the drag.
        noteUserInteraction()

        // If a previous drop animation is still in flight, kill it —
        // grabbing him mid-fall should hand control immediately back
        // to the cursor.
        dropTimer?.invalidate()
        dropTimer = nil

        isDraggingHorizontally = true
        isWalking = false
        isPaused = true
        pauseEndTime = CACurrentMediaTime() + 8.0

        // FUTURE — when justin-picked-up.gif ships, this is the
        // sprite-swap point. Add a "pickup" facing/state to
        // directionalImages and either:
        //   (a) set imageView.image directly here (bypassing setFacing
        //       which is keyed to WalkerFacing), or
        //   (b) extend WalkerFacing with a `.pickedUp` case and
        //       teach setFacing to fall through to it.
        // Until then, the front-facing GIF stands in.
        setFacing(.front)
        continueHorizontalDrag(with: event)
    }

    func continueHorizontalDrag(with event: NSEvent) {
        guard isDraggingHorizontally else { return }
        // Free-fly drag — cursor pulls the character anywhere on
        // screen, not constrained to the dock surface. The per-tick
        // update loop bails on isDraggingHorizontally so this direct
        // window.setFrameOrigin is the sole source of position truth
        // while the user holds the mouse button down.
        let pointerLocation = NSEvent.mouseLocation
        let visualX = pointerLocation.x - displayWidth / 2 - flipXOffset
        // Y: cursor approximately at the character's vertical centre,
        // adjusted for the same `bottomPadding` the docked walking
        // path uses so the character sits naturally relative to the
        // cursor rather than offset to one side.
        let bottomPadding = displayHeight * 0.15
        let visualY = pointerLocation.y - displayHeight / 2 - bottomPadding + yOffset
        window.setFrameOrigin(NSPoint(x: visualX, y: visualY))
        updatePopoverPosition()
        updateThinkingBubble()
        updateExpertNameTag()
    }

    /// Drop to the nearest valid dock position when the user releases
    /// the mouse. Frame-by-frame manual interpolation (60Hz Timer) so
    /// the X and Y axes can carry independent easings — gravity's
    /// physics-correct ease-in-quadratic on Y, smooth ease-out-cubic
    /// on X. The single shared timing curve from NSAnimationContext
    /// always read as a "spring" because the late-acceleration on Y
    /// also snapped X sideways at the very end. Now they're separate.
    ///
    /// Once the drop lands, `isDraggingHorizontally` flips false and
    /// per-tick `update()` resumes — `usesExpandedHorizontalRange` is
    /// also reset to `false`, so the walk loop tracks the dock
    /// dynamically again rather than the full-screen range that the
    /// previous (buggy) drag path leaked.
    func endHorizontalDrag() {
        guard let controller, let metrics = controller.currentDockMetrics() else {
            isDraggingHorizontally = false
            usesExpandedHorizontalRange = false
            return
        }

        let bottomPadding = displayHeight * 0.15
        let dockY = metrics.dockTopY - bottomPadding + yOffset

        // Clamp X to the docked walking range so a release anywhere on
        // screen lands at the closest valid point on the dock. Same
        // range the per-tick update() will use once dragging flips
        // false — snapping the drop endpoint into this range means
        // update() resumes from exactly where the animation ends with
        // no positional jump.
        usesExpandedHorizontalRange = false
        let walkRange = horizontalRangeMetrics(
            screen: metrics.screen,
            dockX: metrics.dockX,
            dockWidth: metrics.dockWidth
        )
        let currentX = window.frame.origin.x
        let currentY = window.frame.origin.y
        let clampedX = max(walkRange.minX, min(currentX, walkRange.minX + walkRange.travelDistance))
        positionProgress = walkRange.travelDistance > 0
            ? (clampedX - walkRange.minX) / walkRange.travelDistance
            : 0

        let targetX = clampedX + flipXOffset
        let targetY = dockY

        // FUTURE — when justin-floating.gif (parachute) ships, this is
        // the swap point. Apply it here, then clear it back to the
        // landing/walking sprite in the completion block below.
        // Pattern matches the planned justin-picked-up swap in
        // beginHorizontalDrag.

        // Physics: d = ½gt² → t = √(2d/g). g = 2400 px/s² calibrated
        // empirically — a 1000px fall reads as ~1 second, matching
        // everyday gravity intuition.
        let fallDistance = max(currentY - targetY, 0)
        let g: CGFloat = 2400
        let physicsDuration = fallDistance > 0 ? sqrt(2 * fallDistance / g) : 0
        let fallDuration = max(0.18, min(Double(physicsDuration), 1.2))

        // Bounce on landing — two diminishing rebounds shaped as
        // parabolic arcs (4·amp·t·(1−t)). First bounce is the visible
        // "boing"; second is a small settle-tick that sells the
        // physics. Coefficients of restitution chosen by feel: ~25%
        // of impact velocity for the first bounce, ~10% for the second,
        // matching how a soft real-world object behaves on a hard
        // surface. Skip bounces entirely on micro-falls (< 60px) —
        // a 6px nudge wouldn't have generated visible bounce energy.
        let bounce1Amp: CGFloat = fallDistance >= 60 ? 18 : 0
        let bounce1Duration: Double = bounce1Amp > 0 ? 0.18 : 0
        let bounce2Amp: CGFloat = fallDistance >= 200 ? 6 : 0
        let bounce2Duration: Double = bounce2Amp > 0 ? 0.11 : 0
        let totalDuration = fallDuration + bounce1Duration + bounce2Duration

        let startX = currentX
        let startY = currentY
        let startTime = CACurrentMediaTime()

        // Cancel any in-flight drop before scheduling a new one.
        dropTimer?.invalidate()

        // 60Hz Timer-driven manual tween. Display vsync isn't required
        // for sub-second animation; a Timer at 16.6ms is visually
        // indistinguishable. The handler interpolates X and Y
        // independently so the curves don't fight each other, and
        // sequences fall → bounce1 → bounce2 → settled across phases.
        dropTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }

            // If user grabbed him mid-fall, abort the drop and let the
            // drag take over. beginHorizontalDrag already invalidates
            // dropTimer, but defend the read here too.
            if self.isDraggingHorizontally == false && self.dropTimer == nil {
                timer.invalidate()
                return
            }
            // Edge case: another beginHorizontalDrag fired and set up a
            // new dropTimer. Bail — the new timer owns the animation.
            if self.dropTimer !== timer {
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            var x: CGFloat
            var y: CGFloat

            if elapsed < fallDuration {
                // Phase 1 — gravity fall.
                let t = CGFloat(elapsed / fallDuration)
                // Y axis: quadratic ease-in. y = t². True uniform
                // gravitational acceleration.
                let yT = t * t
                // X axis: cubic ease-out. Release momentum bleeds out
                // toward the landing point without snapping at the end.
                let xT = 1 - pow(1 - t, 3)
                x = startX + (targetX - startX) * xT
                y = startY + (targetY - startY) * yT
            } else if elapsed < fallDuration + bounce1Duration {
                // Phase 2 — first bounce. Parabolic arc above the
                // dock surface: b(t) = 4·amp·t·(1−t). At t=0 and t=1
                // height is 0 (dock surface); at t=0.5 height = amp.
                let t = CGFloat((elapsed - fallDuration) / bounce1Duration)
                x = targetX
                y = targetY + 4 * bounce1Amp * t * (1 - t)
            } else if elapsed < totalDuration {
                // Phase 3 — settle bounce. Same parabolic shape, smaller
                // amplitude and faster.
                let t = CGFloat((elapsed - fallDuration - bounce1Duration) / bounce2Duration)
                x = targetX
                y = targetY + 4 * bounce2Amp * t * (1 - t)
            } else {
                // Phase 4 — settled. Lock to the dock surface and
                // hand off to the per-tick walk loop.
                x = targetX
                y = targetY
                timer.invalidate()
                self.dropTimer = nil
                self.isDraggingHorizontally = false
                // FUTURE — when justin-landing.gif ships, play it on
                // entry to Phase 2 (impact frame), let it run through
                // the bounce phases, and return to .front here.
                self.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.6...1.4)
            }

            self.window.setFrameOrigin(NSPoint(x: x, y: y))
            self.updatePopoverPosition()
            self.updateThinkingBubble()
            self.updateExpertNameTag()
        }
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
        // All four poses are animated 36-frame GIFs in Orion (vs the
        // upstream Lenny mix of static PNG idles + GIF walks). NSImageView
        // is already configured with `animates = true`, so multi-frame GIFs
        // animate automatically when assigned to `imageView.image`.
        directionalImages[.front] = loadImage(named: "main-front.gif", fallback: "main-front.png")
        directionalImages[.left]  = loadImage(named: "lil-justin-walk-left.gif",  fallback: "main-left.png")
        directionalImages[.right] = loadImage(named: "lil-justin-walk-right.gif", fallback: "main-right.png")
        directionalImages[.back]  = loadImage(named: "main-back.gif",  fallback: "main-back.png")
        // Sleeping idle — used by the sleep state machine when the user
        // hasn't interacted in a while. Cached on first load.
        sleepingImage = loadImage(named: "main-sleeping.gif", fallback: "main-sleeping.png")
    }

    private func loadImage(named name: String, fallback: String? = nil) -> NSImage {
        guard let resourceURL = Bundle.main.resourceURL else {
            return NSImage(size: NSSize(width: displayWidth, height: displayHeight))
        }
        let baseURL = resourceURL.appendingPathComponent(WalkerCharacterAssets.lennyAssetsDirectory)
        let primaryPath = baseURL.appendingPathComponent(name).path
        if let image = NSImage(contentsOfFile: primaryPath) {
            return image
        }
        if let fallback {
            let fallbackPath = baseURL.appendingPathComponent(fallback).path
            if let image = NSImage(contentsOfFile: fallbackPath) {
                return image
            }
        }
        return NSImage(size: NSSize(width: displayWidth, height: displayHeight))
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
            tooltip = "Ask Orion"
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

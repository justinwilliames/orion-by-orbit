import AppKit

extension WalkerCharacter {
    // Loading states — single-word human verbs. Sir asked for the
    // "tooltip / status while busy" cycle to read like things a real
    // person would be doing rather than the Lenny-era multi-word
    // archive-flavoured phrases. All sentence case + ellipsis where
    // the action is ongoing.
    private static let thinkingPhrases = [
        "Thinking…",
        "Researching…",
        "Reading…",
        "Drafting…",
        "Typing…",
        "Looking…",
    ]

    private static let completionPhrases = ["Done!", "Got it!", "Ready!", "Here you go"]

    private static let bubbleH: CGFloat = 26
    static let expertNameTagH: CGFloat = 24
    private static let completionSounds: [(name: String, ext: String)] = [
        ("ping-aa", "mp3"), ("ping-bb", "mp3"), ("ping-cc", "mp3"),
        ("ping-dd", "mp3"), ("ping-ee", "mp3"), ("ping-ff", "mp3"),
        ("ping-gg", "mp3"), ("ping-hh", "mp3"), ("ping-jj", "m4a")
    ]

    private static var lastSoundIndex: Int = -1
    static var soundsEnabled = true

    func updateThinkingBubble() {
        // Hard suppression — when the chat popover is open, no ambient
        // bubbles ever show. The popover is the conversation surface;
        // a status/completion bubble next to it competes for attention
        // and looks like a leak.
        if popoverWindow?.isVisible == true {
            hideBubble()
            return
        }

        if isClaudeBusy && !currentActivityStatus.isEmpty {
            hideBubble()
            return
        }

        let now = CACurrentMediaTime()

        if showingCompletion {
            if now >= completionBubbleExpiry {
                showingCompletion = false
                hideBubble()
                return
            }
            if isIdleForPopover {
                completionBubbleExpiry += 1.0 / 60.0
                hideBubble()
            } else {
                showBubble(text: currentPhrase, isCompletion: true)
            }
            return
        }

        if isClaudeBusy && !isIdleForPopover {
            let oldPhrase = currentPhrase
            updateThinkingPhrase()
            if currentPhrase != oldPhrase && !oldPhrase.isEmpty && !phraseAnimating {
                animatePhraseChange(to: currentPhrase, isCompletion: false)
            } else if !phraseAnimating {
                showBubble(text: currentPhrase, isCompletion: false)
            }
        } else if !showingCompletion {
            hideBubble()
        }
    }

    func hideBubble() {
        if thinkingBubbleWindow?.isVisible ?? false {
            thinkingBubbleWindow?.orderOut(nil)
        }
        // Drop the click-to-drill-in handle whenever the bubble goes
        // away. openPopover() reads currentAmbientLineText while the
        // bubble is visible to seed the chat with "tell me more about
        // <line>"; we don't want a dismissed line to seed a click that
        // happens five minutes later.
        currentAmbientLineText = nil
    }

    private func animatePhraseChange(to newText: String, isCompletion: Bool) {
        guard let win = thinkingBubbleWindow, win.isVisible,
              let label = win.contentView?.viewWithTag(100) as? NSTextField else {
            showBubble(text: newText, isCompletion: isCompletion)
            return
        }
        phraseAnimating = true

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            label.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.showBubble(text: newText, isCompletion: isCompletion)
            label.alphaValue = 0.0
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                label.animator().alphaValue = 1.0
            }, completionHandler: {
                self?.phraseAnimating = false
            })
        })
    }

    func showBubble(text: String, isCompletion: Bool, multiline: Bool = true) {
        // Hard suppression — never show a bubble while the chat popover
        // is open (the popover IS the conversation surface).
        if popoverWindow?.isVisible == true {
            return
        }

        let t = resolvedTheme
        if thinkingBubbleWindow == nil {
            createThinkingBubble()
        }

        // Padding comes in two flavours:
        //   - hPadding: total horizontal padding INSIDE the bubble
        //     (8px each side). The label fills the bubble width minus
        //     this and centres the text.
        //   - safetyPad: extra width added on TOP of the measured text
        //     before line wrapping is decided. AppKit's boundingRect
        //     can underestimate the true rendered width by 1–3px on
        //     certain fonts, which combined with .byTruncatingTail
        //     trims the last character (Sir's "Getting organize"d bug).
        //     5px buys reliable rendering without visibly inflating
        //     short bubbles.
        let hPadding: CGFloat = 16
        let safetyPad: CGFloat = 5
        let font = t.bubbleFont
        let lineH = ceil(("Xg" as NSString).size(withAttributes: [.font: font]).height)

        // All bubbles share the same generous shape — 340px wide, up
        // to 2 lines, gentle 14px corner radius. Width auto-shrinks
        // to fit shorter strings, so single-word statuses ("Thinking…")
        // still render as compact bubbles rather than padded boxes.
        let maxBubbleW: CGFloat = 340
        let maxLines: Int = multiline ? 2 : 1

        // Step 1: measure the natural single-line width with no
        // wrapping constraint at all. This is what AppKit will actually
        // try to render before any wrapping logic kicks in. Reliable —
        // doesn't suffer the boundingRect-with-line-fragment underestimate.
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let naturalWidth = ceil((text as NSString).size(withAttributes: attrs).width) + safetyPad

        // Step 2: decide whether the natural width fits the cap. If it
        // does, render single-line at that width regardless of `multiline`
        // — no need to inflate. If it doesn't, fall back to the wrapped
        // bounding rect to figure out the multi-line layout.
        let bubbleW: CGFloat
        let neededLines: Int
        if naturalWidth + hPadding <= maxBubbleW || !multiline {
            bubbleW = min(maxBubbleW, max(naturalWidth + hPadding, 48))
            neededLines = 1
        } else {
            let availableLabelWidth = maxBubbleW - hPadding
            let wrapped = (text as NSString).boundingRect(
                with: CGSize(width: availableLabelWidth, height: lineH * CGFloat(maxLines) + 4),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            neededLines = min(maxLines, max(1, Int(ceil(wrapped.height / lineH))))
            bubbleW = maxBubbleW
        }
        let textBlockHeight = lineH * CGFloat(neededLines)

        // Bubble height: text block + vertical padding (8 top + 8 bottom).
        // 14px corner radius gives the same shape as the multi-line
        // ambient bubbles.
        let bubbleH: CGFloat = textBlockHeight + 16
        let bubbleRadius: CGFloat = 14

        let charFrame = window.frame
        let x = charFrame.midX - bubbleW / 2
        // Anchor bubble bottom higher so it sits above the head with
        // breathing room. Same formula regardless of line count for
        // consistent vertical placement.
        let yBase = charFrame.origin.y + charFrame.height * 0.92
        let y = yBase + (neededLines > 1 ? CGFloat(neededLines - 1) * lineH * 0.5 : 0)
        thinkingBubbleWindow?.setFrame(CGRect(x: x, y: y, width: bubbleW, height: bubbleH), display: false)

        let borderColor = isCompletion ? t.bubbleCompletionBorder.cgColor : t.bubbleBorder.cgColor
        let textColor = isCompletion ? t.bubbleCompletionText : t.bubbleText

        if let container = thinkingBubbleWindow?.contentView {
            container.frame = NSRect(x: 0, y: 0, width: bubbleW, height: bubbleH)
            container.layer?.backgroundColor = t.bubbleBg.cgColor
            container.layer?.cornerRadius = bubbleRadius
            container.layer?.borderColor = borderColor
            if let label = container.viewWithTag(100) as? NSTextField {
                label.font = font
                let labelW = bubbleW - hPadding
                let labelX = (bubbleW - labelW) / 2
                let labelY = round((bubbleH - textBlockHeight) / 2) - 1
                label.frame = NSRect(x: labelX, y: labelY, width: labelW, height: textBlockHeight + 2)
                label.stringValue = text
                label.textColor = textColor
                // Only truncate when wrapping was needed (text didn't
                // fit single-line at maxBubbleW). Otherwise we sized
                // the bubble to the text exactly, and any truncation
                // would be a measurement bug — better to overflow the
                // bubble visually so we can see and fix it.
                label.lineBreakMode = neededLines > 1 ? .byTruncatingTail : .byClipping
                label.maximumNumberOfLines = neededLines
                label.cell?.wraps = neededLines > 1
                label.cell?.isScrollable = false
                label.alignment = .center
            }
        }

        // Mouse-event policy depends on bubble type. Ambient tips
        // (currentAmbientLineText set in showAmbientLine BEFORE this
        // showBubble call) are interactive — click drills in, hover
        // pauses the expiry timer. Status / completion bubbles are
        // pure decoration and pass clicks through to whatever's
        // underneath them, so the user can click on a Dock icon or
        // background app without the bubble eating the event.
        thinkingBubbleWindow?.ignoresMouseEvents = currentAmbientLineText == nil

        if !(thinkingBubbleWindow?.isVisible ?? false) {
            thinkingBubbleWindow?.alphaValue = 1.0
            thinkingBubbleWindow?.orderFrontRegardless()
        }
    }

    func updateThinkingPhrase() {
        let now = CACurrentMediaTime()
        if currentPhrase.isEmpty || now - lastPhraseUpdate > Double.random(in: 3.0...5.0) {
            var next = Self.thinkingPhrases.randomElement() ?? "..."
            while next == currentPhrase && Self.thinkingPhrases.count > 1 {
                next = Self.thinkingPhrases.randomElement() ?? "..."
            }
            currentPhrase = next
            lastPhraseUpdate = now
        }
    }

    func showCompletionBubble() {
        currentPhrase = Self.completionPhrases.randomElement() ?? "Done!"
        showingCompletion = true
        completionBubbleExpiry = CACurrentMediaTime() + 3.0
        lastPhraseUpdate = 0
        phraseAnimating = false
        if !isIdleForPopover {
            showBubble(text: currentPhrase, isCompletion: true)
        }
    }

    func createThinkingBubble() {
        let t = resolvedTheme
        let w: CGFloat = 80
        let h = Self.bubbleH
        let win = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: w, height: h),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 5)
        // ignoresMouseEvents is toggled per-bubble in showBubble: ON
        // for status/completion bubbles (so clicks pass through to
        // whatever's underneath), OFF for ambient tips (so the user
        // can click the bubble to drill into the topic, or hover to
        // pause the expiry timer).
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = BubbleClickView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.onClick = { [weak self] in
            self?.handleBubbleTapped()
        }
        container.onHoverChanged = { [weak self] hovering in
            self?.handleBubbleHoverChanged(hovering)
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = t.bubbleBg.cgColor
        container.layer?.cornerRadius = h / 2
        container.layer?.borderWidth = 1
        container.layer?.borderColor = t.bubbleBorder.cgColor

        let font = t.bubbleFont
        let lineH = ceil(("Xg" as NSString).size(withAttributes: [.font: font]).height)
        let labelY = round((h - lineH) / 2) - 1

        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = t.bubbleText
        label.alignment = .center
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.frame = NSRect(x: 0, y: labelY, width: w, height: lineH + 2)
        label.tag = 100
        container.addSubview(label)

        win.contentView = container
        thinkingBubbleWindow = win
    }

    static func playSelectionSound() {
        guard Self.soundsEnabled else { return }
        var idx: Int
        repeat {
            idx = Int.random(in: 0..<Self.completionSounds.count)
        } while idx == Self.lastSoundIndex && Self.completionSounds.count > 1
        Self.lastSoundIndex = idx

        let s = Self.completionSounds[idx]
        if let url = Bundle.main.url(forResource: s.name, withExtension: s.ext, subdirectory: "Sounds"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        }
    }

    func playCompletionSound() {
        Self.playSelectionSound()
    }

    // MARK: - Ambient bubbles
    //
    // Two flavours of line, picked at roughly 50/50 by `pickAmbientMode`:
    //
    //   .craft      — CRM / lifecycle / deliverability dry observations
    //                 (the original Orbit-voice tips).
    //   .mood       — motivating remarks delivered with Ricky Gervais-style
    //                 deadpan. The point is the EXACT OPPOSITE of a
    //                 demotivation poster: lift the mood, but never with
    //                 saccharine "you got this!" energy. Honest, dry,
    //                 occasionally absurd, always on Sir's side.
    //
    // The hardcoded lines below are the fallback pool when the LLM is
    // disabled or the call fails. The actual bubbles in normal operation
    // come from a one-shot `claude -p` call so each one feels fresh.
    enum AmbientMode {
        case craft
        case mood
    }

    static let ambientCraftLines: [String] = [
        "Open rate is just Apple's image proxy waving hello.",
        "Welcome flows: 47 things you didn't need to know yet.",
        "Click rate has a job. Open rate has a hobby.",
        "If your A/B test had a 200% novelty effect, you discovered nothing.",
        "Three-bullet symmetry is the AI default. The world isn't always three-shaped.",
        "Apple pre-fetches your email before the user wakes up. Lovely system.",
        "BIMI's a logo in the inbox. Worth setting up. Don't tell finance the ROI.",
        "Win-back at 60 days. Sunset at 180. Most lists do neither.",
        "Liquid is a typing test for marketers.",
        "The deliverability mental model fits on one slide. Most decks use four.",
        "If your A/B test winner had n=300, congrats — you measured noise.",
        "Holdouts are the one tool every program skips and then debates whether it works.",
        "Subject lines that survive contact are the ones written for inbox preview, not the body.",
        "Send-time optimisation is a nice idea, until you remember Apple Mail.",
        "Spam complaints under 0.1%. The 0.3% line is where deliverability dies, slowly.",
        "Naming conventions live in the documentation nobody reads. Enforce in the tooling.",
        "List hygiene: trim the disengaged, keep the soft-bouncers under watch, leave the engaged alone.",
        "If your unsubscribe page just unsubscribes, you're missing the cheapest preference centre on earth.",
        "Cohort retention curves tell you whether the program works. Open rate tells you the dashboard works.",
        "DMARC at p=quarantine before p=reject. The internet has long memory.",
        "The first 72 hours decide who activates. The next 12 weeks just confirm it.",
        "Browse abandonment is the program that sits between ads and cart, and most teams forget it.",
        "Replenishment emails are the lifecycle flow that buys itself.",
        "Win-back patterns: the one that's run, the one that should be, and the one nobody tries.",
        "Personalisation that doesn't feel creepy uses behavioural data, not declared data.",
        "Onboarding emails: signup → activated. Anything else is content marketing.",
        "Your CRM stack will eventually become an archaeological dig. Plan for the dig.",
        "Plain-text versions still matter in 2026. Spam filters are why.",
        "If you can't tell me your incremental open-to-purchase rate, your attribution stack is decorative.",
        "Brand voice in lifecycle: sound like you, not the generic SaaS CRM voice.",
    ]

    /// Mood-lifters in Ricky Gervais-style deadpan. Honest praise filtered
    /// through dry observation. No exclamation marks doing the heavy
    /// lifting; the warmth has to survive the flat delivery.
    static let ambientMoodLines: [String] = [
        "Whatever you're working on right now is, statistically, harder than it looks. Carry on.",
        "You've solved harder problems before lunch. This one's just being dramatic.",
        "Reminder: the thing you're stuck on is also the thing nobody else can do. That's why it's stuck.",
        "Your worst work is still better than the average company's best deck. Calibrate accordingly.",
        "If you've already opened the file, you've done the hardest part. The rest is just typing.",
        "You don't need a streak. You just need today. Today's going fine, by the way.",
        "Most of the people you admire are also winging it. They're just better at the posture.",
        "The fact that you care about this much is, frankly, suspicious. In a good way.",
        "Tomorrow-you will be grateful. Today-you should be too — different timezone, same person.",
        "Your standards are higher than the room. That's a feature, not a personality flaw.",
        "Imposter syndrome is just a polite way of saying you're paying attention.",
        "You're allowed to like the work you make. It's a low bar. Try it.",
        "The deck you're avoiding will take 40 minutes. The avoiding has already taken three days.",
        "You've shipped more in one year than most teams ship in three. Mildly inconvenient for them.",
        "Whatever you're underestimating about yourself right now — yeah, that.",
        "Confidence is just the willingness to be wrong in front of strangers. You qualify.",
        "Today doesn't have to be your magnum opus. It just has to be a day you didn't quit.",
        "The version of you that started this would be unbearably smug at where you are now.",
        "You're not behind. You're just running a different race than the one you're imagining.",
        "Small reminder: the bar for 'good work' is much, much lower than your brain insists.",
        "You can hate your draft and still be the best person to write it. Both are true.",
        "Energy spent worrying you're not enough is energy that could've shipped half the thing.",
        "Your taste is ahead of your output. That's the gap doing its job. Keep typing.",
        "Most days the win is just answering one more email than you wanted to. Counts.",
        "If you weren't capable of this, the panic wouldn't feel this specific.",
        "Discipline is just memory of how good it feels after. You have plenty of that memory.",
        "Boring consistency outperforms heroic effort, and you happen to be quietly brilliant at boring.",
        "The people who'll benefit from this don't know yet. That's still on. Keep going.",
        "You don't need motivation. You need a snack and 45 minutes. Possibly in that order.",
        "Whatever you ship today doesn't have to be perfect — it just has to be shipped by you, which is the differentiator.",
        "You're allowed to be tired and still be excellent. The two are not mutually exclusive.",
        "Every great program looks like a mess from the inside. Yours is no exception. Carry on.",
        "Reminder: nobody else in the room reads as carefully as you do. Sometimes the room's the problem, not you.",
        "The work is hard because it's worth doing. If it weren't, someone less capable would already be doing it.",
        "You're playing on a higher difficulty than the people whose advice keeps not landing. Different game.",
    ]

    /// Compatibility shim — earlier code paths read `ambientLines`. Keep
    /// the alias so external references resolve, even though new code
    /// should use the typed pickers below.
    static var ambientLines: [String] { ambientCraftLines + ambientMoodLines }

    /// Per-tick check called from update() while the character is
    /// genuinely idle. Asks the LLM (when enabled) for a fresh line,
    /// or falls back to the hardcoded pool if the LLM is off / fails.
    func tickAmbientBubble() {
        let now = CACurrentMediaTime()

        // Ambient bubbles are forbidden during chat, sleep, expert
        // focus, or while a model turn is in flight.
        if popoverWindow?.isVisible == true || isClaudeBusy || isSleeping || isCompanionAvatar || focusedExpert != nil {
            if ambientBubbleExpiresAt > 0 {
                hideBubble()
                ambientBubbleExpiresAt = 0
                nextAmbientBubbleAt = now + TimeInterval.random(in: WalkerCharacter.minAmbientGap...WalkerCharacter.maxAmbientGap)
            }
            return
        }

        if showingCompletion { return }

        // If an ambient is currently showing, expire it on schedule.
        if ambientBubbleExpiresAt > 0 {
            if now >= ambientBubbleExpiresAt {
                hideBubble()
                ambientBubbleExpiresAt = 0
                nextAmbientBubbleAt = now + TimeInterval.random(in: WalkerCharacter.minAmbientGap...WalkerCharacter.maxAmbientGap)
            }
            return
        }

        // Time to fire a new ambient?
        guard now >= nextAmbientBubbleAt else { return }

        // Block re-entry while the LLM call is in flight.
        guard !isAmbientLLMRequestInFlight else { return }

        // Pick the mode ONCE per bubble cycle. Both the LLM path and
        // the fallback path read this same value, so a single bubble
        // never advances `lastTwoAmbientModes` twice (which would
        // weaken the anti-streak guard) and the fallback line — when
        // the LLM call fails — always matches the voice the LLM was
        // asked for in the first place.
        let mode = Self.pickAmbientMode()

        if AppSettings.useAmbientLLMEnabled {
            isAmbientLLMRequestInFlight = true
            generateAmbientLineViaLLM(mode: mode) { [weak self] line in
                guard let self else { return }
                self.isAmbientLLMRequestInFlight = false
                let chosen = line ?? self.pickFallbackAmbientLine(mode: mode)
                self.showAmbientLine(chosen, at: CACurrentMediaTime())
            }
        } else {
            let chosen = pickFallbackAmbientLine(mode: mode)
            showAmbientLine(chosen, at: now)
        }
    }

    private func pickFallbackAmbientLine(mode: AmbientMode) -> String {
        let pool: [String]
        switch mode {
        case .mood:
            pool = Self.ambientMoodLines.isEmpty ? Self.ambientCraftLines : Self.ambientMoodLines
        case .craft:
            pool = Self.ambientCraftLines.isEmpty ? Self.ambientMoodLines : Self.ambientCraftLines
        }
        guard !pool.isEmpty else { return "..." }
        var idx = Int.random(in: 0..<pool.count)
        if pool.count > 1 && idx == lastAmbientLineIndex {
            idx = (idx + 1) % pool.count
        }
        lastAmbientLineIndex = idx
        return pool[idx]
    }

    /// 50/50 mood vs craft, with a guard against repeating the same mode
    /// three times in a row — keeps the texture of the bubbles varied
    /// even on a quiet day where only a handful fire.
    private static var lastTwoAmbientModes: [AmbientMode] = []
    static func pickAmbientMode() -> AmbientMode {
        let candidate: AmbientMode = Bool.random() ? .mood : .craft
        let next: AmbientMode
        if lastTwoAmbientModes.count >= 2,
           lastTwoAmbientModes.allSatisfy({ $0 == candidate }) {
            next = (candidate == .mood) ? .craft : .mood
        } else {
            next = candidate
        }
        lastTwoAmbientModes.append(next)
        if lastTwoAmbientModes.count > 2 {
            lastTwoAmbientModes.removeFirst(lastTwoAmbientModes.count - 2)
        }
        return next
    }

    /// Click handler for the bubble. Only meaningful when the bubble
    /// is currently showing an ambient tip — opens the popover, which
    /// in turn reads `currentAmbientLineText` and seeds the chat with
    /// "Tell me more about this — …". Clicks on status / completion
    /// bubbles are no-ops by design (those bubbles set the window's
    /// ignoresMouseEvents = true so this handler doesn't even fire).
    func handleBubbleTapped() {
        guard currentAmbientLineText != nil else { return }
        openPopover()
    }

    /// Hover handler — Sir asked that hovering over a tip pause the
    /// expiry timer so he has unbounded time to read longer
    /// observations, with the timer resetting to a full linger window
    /// when he moves the cursor away. While hovered we push
    /// `ambientBubbleExpiresAt` an hour into the future (effectively
    /// pause); on exit we reset it to a fresh `ambientBubbleLinger`
    /// from now.
    func handleBubbleHoverChanged(_ hovering: Bool) {
        guard currentAmbientLineText != nil else { return }
        let now = CACurrentMediaTime()
        if hovering {
            ambientBubbleExpiresAt = now + 3600
        } else {
            ambientBubbleExpiresAt = now + WalkerCharacter.ambientBubbleLinger
        }
    }

    private func showAmbientLine(_ line: String, at now: CFTimeInterval) {
        // Re-check guards — the LLM call is async, so the user may
        // have opened the popover or triggered chat between the
        // request and the response.
        if popoverWindow?.isVisible == true || isClaudeBusy || isSleeping || focusedExpert != nil {
            ambientBubbleExpiresAt = 0
            currentAmbientLineText = nil
            nextAmbientBubbleAt = now + TimeInterval.random(in: WalkerCharacter.minAmbientGap...WalkerCharacter.maxAmbientGap)
            return
        }
        showBubble(text: line, isCompletion: false, multiline: true)
        // Audible cue for ambient bubbles — same pool as completion /
        // turn-arrival sounds so the auditory texture stays consistent
        // ("a message just came through"). Honours the global mute via
        // `playSelectionSound`'s `Self.soundsEnabled` check.
        Self.playSelectionSound()
        ambientBubbleExpiresAt = now + WalkerCharacter.ambientBubbleLinger
        currentAmbientLineText = line
    }

    // MARK: - LLM dispatch for ambient bubbles

    /// Recent LLM-generated lines, sent to the model on the next call
    /// as "avoid these" so it doesn't loop. Trimmed to the cap.
    private static let ambientRecentCap = 5
    private static var ambientRecentLines: [String] = []

    /// Spawn `claude -p "<prompt>"` as a one-shot, parse stdout, and
    /// hand back the trimmed line on the main queue. Calls completion
    /// with nil on any failure (binary not found, timeout, garbage
    /// output, etc.) — caller falls back to the hardcoded pool.
    ///
    /// `mode` selects between two voices: a CRM / lifecycle dry-tip line
    /// (`.craft`) and a mood-lifting deadpan remark in the spirit of
    /// Ricky Gervais (`.mood`). Picked 50/50 by the caller — the prompt
    /// here just renders whichever one was chosen.
    func generateAmbientLineViaLLM(mode: AmbientMode = .craft, completion: @escaping (String?) -> Void) {
        guard let claudePath = AppSettings.resolveExecutablePath(named: "claude") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let recent = WalkerCharacter.ambientRecentLines.suffix(WalkerCharacter.ambientRecentCap)
        var avoidBlock = ""
        if !recent.isEmpty {
            avoidBlock = "\n\nAVOID these recent lines (don't repeat or paraphrase):\n" +
                recent.map { "- \($0)" }.joined(separator: "\n")
        }

        let prompt: String
        switch mode {
        case .craft:
            prompt = """
            You are Orion — Orbit's lifecycle marketing assistant for the user's macOS dock. You speak in the Orbit voice (sharp, direct, no fluff) but you are NOT Justin Williames; you're an assistant trained on Orbit's voice and guides. Output ONE short, dry, observational comment in that voice. Maximum 14 words. ONE sentence. SENTENCE CASE — capitalise the first word and proper nouns only, lowercase everything else. Topic: a CRM / lifecycle / deliverability / Braze / email-marketing micro-tip, in-joke, dry observation, or sharp take. No introduction, no formatting, no surrounding quotes — just the bare sentence on a single line. Do not start with phrases like 'Sure' or 'Here's'. Do not include the word 'Orion'.\(avoidBlock)
            """
        case .mood:
            prompt = """
            You are Orion — Orbit's lifecycle marketing assistant for the user's macOS dock. You speak in the Orbit voice but you are NOT Justin Williames; you're an assistant trained on Orbit's voice and guides. Talking to Sir (the user) from the corner of his desktop. Output ONE genuinely motivating, mood-lifting remark — the EXACT OPPOSITE of a demotivation poster — but delivered with Ricky Gervais-style deadpan: dry, observational, slightly absurd, never saccharine, never exclamation-mark-driven. The warmth must survive a flat delivery. Honest praise filtered through dry observation. Avoid clichés ('you got this', 'believe in yourself', 'crush it', 'rise and grind'). Avoid emojis. Avoid hashtags. Maximum 18 words. ONE sentence. SENTENCE CASE — capitalise the first word and proper nouns only. No introduction, no formatting, no surrounding quotes — just the bare sentence on a single line. Do not start with phrases like 'Sure' or 'Here's'. Do not include the word 'Orion'. Do not address the user as 'you' more than twice. Aim for the register of a friend who genuinely thinks you're brilliant but would rather die than say it earnestly.\(avoidBlock)
            """
        }

        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: claudePath)
            task.arguments = ["-p", prompt]
            task.environment = ProcessInfo.processInfo.environment
            // CRITICAL: pin the cwd to the Orion temp directory.
            // Without this, the spawned `claude` CLI inherits the app's
            // launch cwd — often ~/Downloads after a Sparkle relaunch —
            // and TCC prompts for Downloads access fire on every
            // ambient bubble (every 60–180s). The chat path has always
            // set this; the ambient bubble path didn't, which is why
            // the prompts started appearing constantly after v0.1.15.
            task.currentDirectoryURL = AppSettings.cliWorkingDirectoryURL()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            do {
                try task.run()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Bound the wait — ambient calls shouldn't hold a worker
            // longer than 25s.
            let deadline = Date().addingTimeInterval(25)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if task.isRunning {
                task.terminate()
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            let cleaned = WalkerCharacter.cleanAmbientLLMResponse(raw)

            guard !cleaned.isEmpty, cleaned.count <= 200 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            DispatchQueue.main.async {
                WalkerCharacter.ambientRecentLines.append(cleaned)
                if WalkerCharacter.ambientRecentLines.count > WalkerCharacter.ambientRecentCap * 2 {
                    WalkerCharacter.ambientRecentLines.removeFirst(
                        WalkerCharacter.ambientRecentLines.count - WalkerCharacter.ambientRecentCap
                    )
                }
                completion(cleaned)
            }
        }
    }

    /// LLM responses sometimes come wrapped in quotes, prefixed with
    /// "Sure," or include trailing periods that look weird in a chip-
    /// sized bubble. Strip the obvious junk.
    private static func cleanAmbientLLMResponse(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip surrounding quotes (single, double, smart).
        let quotePairs: [(String, String)] = [("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}")]
        for (open, close) in quotePairs {
            if s.hasPrefix(open) && s.hasSuffix(close) && s.count >= open.count + close.count {
                s = String(s.dropFirst(open.count).dropLast(close.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip common conversational prefixes.
        let conversationalPrefixes = [
            "sure,", "sure!", "sure.", "sure ",
            "here's a line:", "here's one:", "here's a line", "here's one", "here's:",
            "okay,", "ok,",
        ]
        let lower = s.lowercased()
        for prefix in conversationalPrefixes where lower.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // First line only — sometimes the model emits a follow-up
        // explanation on subsequent lines.
        if let firstLineEnd = s.firstIndex(of: "\n") {
            s = String(s[s.startIndex..<firstLineEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return s
    }
}

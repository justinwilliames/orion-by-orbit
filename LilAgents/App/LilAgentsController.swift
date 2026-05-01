import AppKit

class LilAgentsController {
    var characters: [WalkerCharacter] = []
    private var displayLink: CVDisplayLink?
    private var fallbackDisplayTimer: Timer?
    private var lastTickTimestamp: CFTimeInterval = 0
    var debugWindow: NSWindow?
    var pinnedScreenIndex: Int = -1
    private static let onboardingKey = "hasCompletedOnboarding"
    private let maxVisibleGuestAvatars = 3
    private var currentExperts: [ResponderExpert] = []
    var suggestedExperts: [ResponderExpert] { Array(currentExperts.prefix(maxVisibleGuestAvatars)) }
    var onExpertsChanged: (([ResponderExpert]) -> Void)?
    var onFocusedExpertChanged: ((ResponderExpert?) -> Void)?
    private(set) var focusedExpert: ResponderExpert?

    func start() {
        let justin = WalkerCharacter(videoName: "justin")
        justin.accelStart = 2.5
        justin.fullSpeedStart = 3.2
        justin.decelStart = 7.8
        justin.walkStop = 8.4
        justin.walkAmountRange = 0.35...0.6
        justin.yOffset = 4
        justin.characterColor = NSColor(red: 0.96, green: 0.63, blue: 0.23, alpha: 1.0)
        justin.positionProgress = 0.9
        justin.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.5...2.0)
        justin.setup()

        characters = [justin]
        characters.forEach { $0.controller = self }

        setupDebugLine()
        startDisplayLink()
        registerDockRefreshObservers()
        wireQuickToolHooks()

        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            triggerOnboarding()
        }
    }

    /// Hook PomodoroController and CalendarTooltipProvider into the
    /// character — the controllers don't depend on AppKit types
    /// directly, so the wiring lives here.
    private func wireQuickToolHooks() {
        PomodoroController.shared.onTickRefresh = { [weak self] text, phase in
            guard let bruce = self?.characters.first else { return }
            switch phase {
            case .idle:
                // Pomodoro stopped (or finished). Release every hold so
                // the regular bubble + sleep lifecycle takes back over.
                bruce.pomodoroBubbleHold = false
                bruce.pomodoroForceAwake = false
                bruce.pomodoroForceAsleep = false
                return
            case .focus:
                // Stay awake for the whole focus phase + claim the
                // bubble surface for the red countdown.
                bruce.pomodoroBubbleHold = true
                bruce.pomodoroForceAwake = true
                bruce.pomodoroForceAsleep = false
                if bruce.isSleeping { bruce.wakeUp() }
                // Yield to the chat thinking bubble and to the per-phase
                // completion bubble (which has its own 6s expiry and
                // text). After either expires, the next tick (within 1s)
                // re-asserts the countdown.
                if bruce.isClaudeBusy { return }
                if bruce.showingCompletion { return }
                bruce.currentPhrase = text
                bruce.showBubble(text: text, isCompletion: false, tint: .systemRed)
            case .shortBreak, .longBreak:
                // Sleep for the whole break + claim the bubble surface
                // for the green countdown. enterSleep respects
                // pomodoroBubbleHold and won't hide the countdown.
                bruce.pomodoroBubbleHold = true
                bruce.pomodoroForceAwake = false
                bruce.pomodoroForceAsleep = true
                if !bruce.isSleeping { bruce.enterSleep() }
                if bruce.isClaudeBusy { return }
                if bruce.showingCompletion { return }
                bruce.currentPhrase = text
                bruce.showBubble(text: text, isCompletion: false, tint: .systemGreen)
            }
        }
        PomodoroController.shared.onPhaseEnd = { [weak self] ended, next, completionText in
            guard let bruce = self?.characters.first else { return }
            bruce.playCompletionSound()
            // Routine focus↔rest boundaries: chime only. Skip the 6s
            // completion bubble so the live countdown swaps cleanly
            // from "Focus 0:00" red → "Rest 5:00" green on the next
            // tick. Long-break milestones still get the celebratory
            // bubble — they fire once per ~2 hours, not on the loop.
            let routineLoop = (ended == .focus && next == .shortBreak)
                || (ended == .shortBreak && next == .focus)
            if routineLoop { return }
            bruce.currentPhrase = completionText
            bruce.showingCompletion = true
            bruce.completionBubbleExpiry = CACurrentMediaTime() + 6.0
            bruce.showBubble(text: completionText, isCompletion: true)
        }

        CalendarTooltipProvider.shared.onTooltipText = { [weak self] text in
            self?.characters.first?.window?.contentView?.toolTip = text
        }
        CalendarTooltipProvider.shared.start()
    }

    private func triggerOnboarding() {
        guard let bruce = characters.first else { return }
        bruce.isOnboarding = true
        // Show "Hi!" bubble after a short delay so the character is visible first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak bruce] in
            guard let bruce else { return }
            bruce.currentPhrase = "Hi!"
            bruce.showingCompletion = true
            bruce.completionBubbleExpiry = CACurrentMediaTime() + 600 // stays until clicked
            bruce.showBubble(text: "Hi!", isCompletion: true)
            bruce.playCompletionSound()
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        characters.forEach { $0.isOnboarding = false }
    }

    func updateExperts(_ experts: [ResponderExpert]) {
        currentExperts = experts
        onExpertsChanged?(experts)
        if focusedExpert != nil {
            syncGuestCharacters()
        } else {
            hideCompanionAvatars()
        }
    }

    func returnToGenie() {
        focus(on: nil)
    }

    func debugExpertSuggestions() -> [ResponderExpert] {
        let session = ClaudeSession()
        let names = ["Claire Butler", "Madhavan Ramanujam", "Patrick Campbell"]

        let experts = names.compactMap { name -> ResponderExpert? in
            guard let avatarPath = session.avatarPath(for: name) ?? session.genericExpertAvatarPath() else { return nil }
            return ResponderExpert(
                name: name,
                avatarPath: avatarPath,
                archiveContext: "Debug expert suggestion preview for \(name).",
                responseScript: "Debug expert handoff for \(name)."
            )
        }

        updateExperts(experts)
        return experts
    }

    func clearDebugExpertSuggestions() {
        updateExperts([])
    }

    func focus(on expert: ResponderExpert?) {
        focusedExpert = expert
        onFocusedExpertChanged?(expert)
        guard let character = characters.first else { return }
        character.focus(on: expert)
        syncGuestCharacters()
    }

    func openDialog(for expert: ResponderExpert?) {
        guard let expert else {
            focus(on: nil)
            return
        }

        if let character = characters.first(where: { candidate in
            if candidate === characters.first {
                return candidate.focusedExpert == expert
            }
            return candidate.isCompanionAvatar && candidate.representedExpert == expert
        }) {
            character.focusedExpert = expert
            character.claudeSession?.focusedExpert = expert
            character.openPopover()
            return
        }

        focus(on: expert)
    }

    private func syncGuestCharacters() {
        guard focusedExpert == nil else {
            hideCompanionAvatars()
            return
        }
        hideCompanionAvatars()
    }

    private func hideCompanionAvatars() {
        guard characters.count > 1 else { return }
        for companion in characters.dropFirst() {
            companion.hideCompanionAvatar()
        }
    }

    func currentDockMetrics() -> (screen: NSScreen, dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat)? {
        guard let screen = activeScreen else { return nil }

        let dockX: CGFloat
        let dockWidth: CGFloat
        let dockTopY: CGFloat

        if screenHasDock(screen) {
            // Prefer the Window Server's actual pill rectangle (the
            // visible glass tile container behind the icons). When that
            // query returns nil — auto-hide on, transient state during a
            // pref change, or some future privacy gate — fall back to
            // the upstream Lil-Lenny estimator that reads dock prefs.
            if let pill = dockPillBounds(screen: screen) {
                dockX = pill.origin.x
                dockWidth = pill.width
                dockTopY = pill.maxY
            } else {
                (dockX, dockWidth) = getDockIconArea(screen: screen)
                dockTopY = screen.visibleFrame.origin.y
            }
        } else {
            let margin: CGFloat = 40.0
            dockX = screen.frame.origin.x + margin
            dockWidth = screen.frame.width - margin * 2
            dockTopY = screen.frame.origin.y
        }

        return (screen, dockX, dockWidth, dockTopY)
    }

    // MARK: - Debug

    private func setupDebugLine() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 2),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.red
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.orderOut(nil)
        debugWindow = win
    }

    private func updateDebugLine(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        guard let win = debugWindow, win.isVisible else { return }
        win.setFrame(CGRect(x: dockX, y: dockTopY, width: dockWidth, height: 2), display: true)
    }

    // MARK: - Dock prefs cache invalidation

    /// Force cfprefsd to flush its cache for com.apple.dock so the
    /// next read picks up icon adds/removes immediately. Called on
    /// app activation, on the dock's own prefs-changed distributed
    /// notification, and at intervals from the tick loop.
    @objc func refreshDockPreferences() {
        let dockDomain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dockDomain)
    }

    /// Wired up once at start(). Subscribes to:
    ///   - NSApplication.didBecomeActiveNotification — fires when
    ///     Orion returns to foreground (clicks into the popover,
    ///     etc.). Refresh first thing.
    ///   - DistributedNotificationCenter "com.apple.dock.prefchanged"
    ///     — the Dock app posts this whenever it writes new prefs
    ///     (icons added/removed/reordered, tile size changed).
    func registerDockRefreshObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshDockPreferences),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(refreshDockPreferences),
            name: NSNotification.Name("com.apple.dock.prefchanged"),
            object: nil
        )
        // One initial sync so the first tick after launch already
        // sees any pending updates that landed before Orion
        // attached its observers.
        refreshDockPreferences()
    }

    // Helpers — read Dock prefs via CFPreferences directly. Bypasses
    // UserDefaults' per-process cache so updates from the Dock app
    // propagate within one tick after refreshDockPreferences fires.
    private func readDockNumber(key: String, default fallback: Double) -> Double {
        let dockDomain = "com.apple.dock" as CFString
        if let value = CFPreferencesCopyAppValue(key as CFString, dockDomain) as? NSNumber {
            return value.doubleValue
        }
        return fallback
    }

    private func readDockBool(key: String, default fallback: Bool) -> Bool {
        let dockDomain = "com.apple.dock" as CFString
        if let value = CFPreferencesCopyAppValue(key as CFString, dockDomain) as? NSNumber {
            return value.boolValue
        }
        return fallback
    }

    private func readDockArrayCount(key: String) -> Int {
        let dockDomain = "com.apple.dock" as CFString
        if let value = CFPreferencesCopyAppValue(key as CFString, dockDomain) as? [Any] {
            return value.count
        }
        return 0
    }

    // MARK: - Dock Pill Detection (Window Server)

    /// Last pill rect we wrote to NSLog. Used to suppress per-tick log
    /// spam — we only emit a diagnostic line when the bounds actually
    /// move (icon added/removed, magnification settle, screen change).
    private var lastLoggedPillBounds: CGRect?

    /// Asks the Window Server for the visible Dock pill — the
    /// translucent glass tile container that sits behind the icons.
    /// Returns Cocoa-coordinate bounds (bottom-left origin, same as
    /// NSScreen.frame).
    ///
    /// Selection criterion is the canonical dock window level
    /// (`CGWindowLevelForKey(.dockWindow)`) plus an alpha + screen-edge
    /// + sane-size sanity filter. Prior CGWindowList attempts (v0.1.57,
    /// v0.1.59) used area / width heuristics within the matching set
    /// and picked the wrong sibling — an oversized click-catcher in
    /// one case, a smaller auxiliary window in the other. Filtering by
    /// the canonical level eliminates that whole class of mistake.
    ///
    /// Diagnostic candidates are NSLog'd whenever the picked pill moves
    /// (or no pill is found), tagged with "[Orion]" — visible in
    /// Console.app via Action ▸ Include Info Messages, filter "Orion".
    /// If a future macOS reshapes the Dock window topology we can read
    /// the log and adjust the filter without another full revert.
    ///
    /// Returns nil when:
    ///   - The Dock is auto-hidden (no on-screen pill)
    ///   - The Window Server returns no Dock-owned windows (rare)
    ///   - No qualified candidate matches the filter
    private func dockPillBounds(screen: NSScreen) -> CGRect? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }

        let dockWindows = raw.filter { ($0[kCGWindowOwnerName as String] as? String) == "Dock" }
        let primary = NSScreen.screens.first ?? screen
        let primaryHeight = primary.frame.height

        // Quartz coords have top-left origin anchored to the primary
        // display. Convert the screen's bottom edge into Quartz Y once.
        let screenBottomQuartz = primaryHeight - screen.frame.origin.y
        let screenLeft = screen.frame.origin.x
        let screenRight = screen.frame.maxX
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

        var qualified: [(rect: CGRect, alpha: Double, name: String)] = []
        var diagLines: [String] = []

        for w in dockWindows {
            guard let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let layer = (w[kCGWindowLayer as String] as? Int) ?? Int.min
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1.0
            let name = (w[kCGWindowName as String] as? String) ?? ""

            let onThisScreen = rect.maxX > screenLeft && rect.minX < screenRight
            let visible = alpha > 0.5
            let levelMatch = layer == dockLevel
            let bottomQuartz = rect.origin.y + rect.height
            let edgeMatch = abs(bottomQuartz - screenBottomQuartz) <= 4
            let heightOk = rect.height >= 30 && rect.height <= 220
            let widthOk = rect.width >= 200

            let isQualified = onThisScreen && visible && levelMatch && edgeMatch && heightOk && widthOk
            diagLines.append("  \(isQualified ? "*" : " ") layer=\(layer) alpha=\(String(format: "%.2f", alpha)) name=\"\(name)\" bounds=\(rect)")

            if isQualified { qualified.append((rect, alpha, name)) }
        }

        guard let pill = qualified.max(by: { $0.rect.width < $1.rect.width }) else {
            if lastLoggedPillBounds != nil {
                lastLoggedPillBounds = nil
                NSLog("[Orion] Dock pill: NO MATCH (level=\(dockLevel), bottomQuartz=\(screenBottomQuartz))\n" + diagLines.joined(separator: "\n"))
            }
            return nil
        }

        // Convert Quartz rect → Cocoa rect for downstream consumers.
        let cocoaY = primaryHeight - (pill.rect.origin.y + pill.rect.height)
        let cocoaRect = CGRect(x: pill.rect.origin.x, y: cocoaY, width: pill.rect.width, height: pill.rect.height)

        let changed: Bool
        if let last = lastLoggedPillBounds {
            changed = abs(last.origin.x - cocoaRect.origin.x) > 2
                || abs(last.origin.y - cocoaRect.origin.y) > 2
                || abs(last.width - cocoaRect.width) > 2
                || abs(last.height - cocoaRect.height) > 2
        } else {
            changed = true
        }

        if changed {
            lastLoggedPillBounds = cocoaRect
            NSLog("[Orion] Dock pill picked: \(cocoaRect) (level=\(dockLevel))\n" + diagLines.joined(separator: "\n"))
        }

        return cocoaRect
    }

    // MARK: - Dock Geometry

    private func getDockIconArea(screen: NSScreen) -> (x: CGFloat, width: CGFloat) {
        // Reverted to the upstream Lil-Lenny estimator after my
        // attempts to "do better" via CGWindowListCopyWindowInfo
        // (v0.1.57, v0.1.59) each picked a wrong-sized Dock-owned
        // window — first too wide (click-catcher layer), then too
        // narrow (smallest-width matching window).
        //
        // Reads use CFPreferencesCopyAppValue rather than
        // UserDefaults(suiteName:) — the latter has a per-process
        // cache that doesn't always invalidate when the Dock app
        // writes new prefs (e.g. when Sir drag-removes an icon).
        // CFPreferencesCopyAppValue hits cfprefsd directly each call
        // so changes show up on the next tick after a sync, no app
        // restart needed.
        let dockDomain = "com.apple.dock" as CFString

        let tileSize = CGFloat(readDockNumber(key: "tilesize", default: 48))
        // Each dock slot is the icon + padding. The padding scales with tile size.
        // At default 48pt: slot ≈ 58pt. At 37pt: slot ≈ 47pt. Roughly tileSize * 1.25.
        let slotWidth = tileSize * 1.25

        let persistentApps = readDockArrayCount(key: "persistent-apps")
        let persistentOthers = readDockArrayCount(key: "persistent-others")
        let showRecents = readDockBool(key: "show-recents", default: true)
        let recentApps = showRecents ? readDockArrayCount(key: "recent-apps") : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        // show-recents adds its own divider
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12.0
        var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth
        let edgePadding = max(14.0, tileSize * 0.28)

        let magnificationEnabled = readDockBool(key: "magnification", default: false)
        if magnificationEnabled {
            // Magnification only affects the hovered area; at rest the dock is normal size.
            // Don't inflate the width — characters should stay within the at-rest bounds.
            _ = readDockNumber(key: "largesize", default: 0)
        }
        _ = dockDomain  // referenced by helpers below — keeps intent clear

        if totalIcons == 0 {
            dockWidth = max(220.0, tileSize * 4.0)
        } else {
            dockWidth += edgePadding * 2.0
        }

        let maximumDockWidth = screen.visibleFrame.width - 24.0
        // Restored upstream's 45%-of-screen floor. v0.1.55 removed
        // it on a misread of Sir's "going outside the dock" report
        // (which was about popover positioning, not horizontal
        // drift). The floor gives the character a generous walking
        // range even when the dock has few icons; on dense docks
        // the actual icon-count math wins.
        let minimumUsableWidth = max(220.0, min(screen.visibleFrame.width - 48.0, screen.frame.width * 0.45))
        if dockWidth < minimumUsableWidth {
            dockWidth = minimumUsableWidth
        }

        dockWidth = min(dockWidth, maximumDockWidth)
        let dockX = screen.frame.midX - dockWidth / 2.0
        return (dockX, dockWidth)
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        startFallbackDisplayTimer()
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let controller = Unmanaged<LilAgentsController>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick(source: .displayLink)
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
                                       Unmanaged.passUnretained(self).toOpaque())
        _ = CVDisplayLinkStart(displayLink)
    }

    private func startFallbackDisplayTimer() {
        fallbackDisplayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick(source: .fallbackTimer)
        }
        fallbackDisplayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    var activeScreen: NSScreen? {
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return NSScreen.screens[pinnedScreenIndex]
        }
        // Default — anchor to the screen that owns the Dock, not the
        // screen with the active window. macOS shows the Dock on
        // exactly one screen (System Settings → Displays → "Dock at
        // bottom of [screen]"); using NSScreen.main makes Orion
        // follow Sir's cursor / focused window across extended
        // displays, jumping monitors every time he switches apps.
        // Pinning to the dock screen keeps him where the dock is.
        if let dockScreen = NSScreen.screens.first(where: screenHasDock) {
            return dockScreen
        }
        // Fallback — no screen reports a dock inset (auto-hide on,
        // unusual multi-monitor config). Use main rather than nil
        // so the character still has somewhere to render.
        return NSScreen.main
    }

    /// True when `screen` has a visible Dock attached. macOS reports the
    /// Dock as a frame inset on the side it lives on (bottom = origin.y
    /// raised, left = origin.x raised, right = maxX shortened). Checks
    /// all three orientations so Orion follows the Dock wherever Sir
    /// puts it.
    private func screenHasDock(_ screen: NSScreen) -> Bool {
        let f = screen.frame
        let v = screen.visibleFrame
        if v.origin.y > f.origin.y { return true }   // bottom dock
        if v.origin.x > f.origin.x { return true }   // left dock
        if v.maxX < f.maxX { return true }           // right dock
        return false
    }

    private enum TickSource {
        case displayLink
        case fallbackTimer
    }

    private func tick(source: TickSource) {
        let now = CACurrentMediaTime()
        if source == .fallbackTimer, now - lastTickTimestamp < (1.0 / 90.0) {
            return
        }
        lastTickTimestamp = now

        guard let metrics = currentDockMetrics() else { return }
        let screen = metrics.screen
        let dockX = metrics.dockX
        let dockWidth = metrics.dockWidth
        let dockTopY = metrics.dockTopY

        updateDebugLine(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)

        let activeChars = characters.filter { $0.window.isVisible }
        let anyWalking = activeChars.contains { $0.isWalking }
        for char in activeChars {
            if char.isIdleForPopover { continue }
            if char.isPaused && now >= char.pauseEndTime && anyWalking {
                char.pauseEndTime = now + Double.random(in: 5.0...10.0)
            }
        }
        for char in activeChars {
            char.update(screen: screen, dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
        }

        let sorted = activeChars.sorted { $0.positionProgress < $1.positionProgress }
        for (i, char) in sorted.enumerated() {
            char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + i)
        }
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        fallbackDisplayTimer?.invalidate()
    }
}

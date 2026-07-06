import SwiftUI
import AppKit
import Sparkle

@main
struct OrionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    var controller: OrionController?
    var statusItem: NSStatusItem?
    /// Owns the menubar-summoned chat popover. Retained for the app's
    /// lifetime; instantiated once in applicationDidFinishLaunching after
    /// the controller exists. Additive — the sprite's click-to-chat path
    /// is unchanged.
    var chatPopoverController: ChatPopoverController?
    /// The NSMenu built in setupMenuBar(). No longer assigned to
    /// statusItem.menu (that would make every click pop the menu and
    /// swallow the button action). Instead we pop it manually on
    /// right-click; left-click toggles the chat popover.
    var statusMenu: NSMenu?
    var expertStatusItems: [NSStatusItem] = []
    var visibleExperts: [ResponderExpert] = []
    var focusedExpert: ResponderExpert?
    var settingsWindow: NSWindow?
    var char1Item: NSMenuItem?
    var backToCharacterItem: NSMenuItem?
    var installUpdateItem: NSMenuItem?
    var pendingScheduledUpdate = false
    var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        // Sparkle auto-update is live as of v0.1.12. The full pipeline:
        //   1. Info.plist: SUFeedURL → /releases/latest/download/appcast.xml,
        //      SUPublicEDKey baked in.
        //   2. CI workflow signs every tagged .dmg with the matching
        //      Ed25519 private key (SPARKLE_ED_PRIVATE_KEY repo secret)
        //      and attaches appcast.xml as a release asset.
        //   3. SPUStandardUpdaterController kicks an automatic check on
        //      launch and again every SUScheduledCheckInterval seconds
        //      (24h, set in Info.plist). User can also trigger via
        //      'Check for Updates…' in the menubar.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSettings.prefetchDetectionState()
        // Warm the Orbit guides embedding cache on a background queue.
        // First run computes 87 vectors (milliseconds with Apple's
        // built-in NLEmbedding) and persists them to App Support.
        // Subsequent launches hit the disk cache. Until vectors are
        // ready, retrieval falls back to keyword-only — so this is
        // pure upside, never a startup blocker.
        OrbitGuidesEmbeddings.precomputeIfNeeded()
        // Reconcile the OS login-item registration with the user's
        // preference. Default for first-install users is ON — the
        // first call here registers the app with macOS, which surfaces
        // the Login Items approval prompt in System Settings.
        AppSettings.applyLaunchAtLoginPreference()
        // Detect post-Sparkle-update launches and surface the
        // Gatekeeper-bypass help dialog so users don't have to remember
        // the xattr command after every auto-update. Skipped on first
        // install (no previously-seen version) and on dev builds where
        // Xcode might rewrite the bundle without changing the version.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkForPostUpdateGatekeeperHelp()
        }
        controller = OrionController()
        NotificationCenter.default.addObserver(self, selector: #selector(handleResetAllData), name: .liLJustinDidResetData, object: nil)
        controller?.onExpertsChanged = { [weak self] experts in
            self?.updateExpertStatusItems(experts)
        }
        controller?.onFocusedExpertChanged = { [weak self] expert in
            self?.updateFocusedExpert(expert)
        }
        controller?.start()
        chatPopoverController = ChatPopoverController(controller: controller)
        setupMenuBar()

        // Follow the system light/dark appearance live. The active Orbit
        // theme (PopoverTheme.current) resolves dark/light from the
        // effective appearance at popover-creation time; when the user
        // flips the system theme while a popover is open we rebuild it
        // through the same proven recreate path used by the Style menu.
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func systemAppearanceChanged() {
        // The distributed notification can arrive before NSApp's
        // effectiveAppearance updates; hop to the next runloop so the
        // resolver reads the new appearance.
        DispatchQueue.main.async { [weak self] in
            guard PopoverTheme._currentOverride == nil else { return }
            self?.rebuildOpenPopovers()
        }
    }

    /// Tear down and recreate any open chat popover so it re-reads the
    /// active theme. Shared by the Style menu and the system-appearance
    /// observer.
    func rebuildOpenPopovers() {
        controller?.characters.forEach { char in
            let wasOpen = char.isIdleForPopover
            if wasOpen { char.popoverWindow?.orderOut(nil) }
            char.popoverWindow = nil
            char.terminalView = nil
            char.thinkingBubbleWindow = nil
            if wasOpen {
                char.createPopoverWindow()
                if let session = char.claudeSession, !session.history.isEmpty {
                    char.terminalView?.replayHistory(session.history)
                }
                char.updatePopoverPosition()
                char.popoverWindow?.orderFrontRegardless()
                char.popoverWindow?.makeKey()
                if let terminal = char.terminalView {
                    char.popoverWindow?.makeFirstResponder(terminal.inputField)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.characters.forEach { $0.claudeSession?.terminate() }
    }

    @objc private func handleResetAllData() {
        controller?.returnToGenie()
        controller?.clearDebugExpertSuggestions()

        controller?.characters.forEach { character in
            character.claudeSession?.terminate()
            character.claudeSession = nil
            character.terminalView?.endStreaming()
            character.terminalView?.clearLiveStatus()
            character.terminalView?.hideExpertSuggestions()
            character.terminalView?.requiresInitialConnectionSetup = false
            if character.isIdleForPopover {
                character.terminalView?.showWelcomeGreeting(forceRefresh: true)
                // Immediately recreate the session so the user can send a message
                // without hitting nil → perpetual spinner (isStreaming=true, send dropped).
                let session = ClaudeSession()
                session.focusedExpert = character.focusedExpert
                character.claudeSession = session
                character.wireSession(session)
                session.start()
            }
        }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Orbit")
            // isTemplate = true → AppKit auto-tints the alpha channel
            // black in light-mode menu bars, white in dark-mode menu
            // bars. macOS standard. Without this the icon stays a fixed
            // colour and stops being legible against the wrong-mode
            // wallpaper. Requires the MenuBarIcon asset to be monochrome
            // (alpha-only); SF Symbols already template-render correctly.
            button.image?.isTemplate = true
            button.toolTip = "Open Orbit chat"
            // Left-click → toggle the chat popover; right-click → the
            // classic menu. We do NOT assign statusItem.menu (that makes
            // AppKit pop the menu on every click and never fire the button
            // action); instead the action below pops the menu manually on
            // right-click. sendAction(on:) makes the action fire on the
            // mouse-DOWN of both buttons so we can branch on event type.
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        let menu = NSMenu()

        // PHASE 2 — the "Show Orion" / "Back to Orion" sprite show/hide
        // toggles are gone: there is no visible sprite to show or hide, and
        // left-clicking the menubar button now opens the chat directly.

        let soundItem = NSMenuItem(title: "Sounds", action: #selector(toggleSounds(_:)), keyEquivalent: "")
        soundItem.state = .on
        menu.addItem(soundItem)

        // Theme submenu
        let themeItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for (i, theme) in PopoverTheme.allThemes.enumerated() {
            let item = NSMenuItem(title: theme.name, action: #selector(switchTheme(_:)), keyEquivalent: "")
            item.tag = i
            item.state = i == 0 ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        // Display submenu
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        displayMenu.delegate = self
        let autoItem = NSMenuItem(title: "Auto (Main Display)", action: #selector(switchDisplay(_:)), keyEquivalent: "")
        autoItem.tag = -1
        autoItem.state = .on
        displayMenu.addItem(autoItem)
        displayMenu.addItem(NSMenuItem.separator())
        for (i, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName
            let item = NSMenuItem(title: name, action: #selector(switchDisplay(_:)), keyEquivalent: "")
            item.tag = i
            item.state = .off
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        if AppSettings.showsDeveloperTools {
            menu.addItem(NSMenuItem.separator())

            let debugShowExpertsItem = NSMenuItem(title: "Debug Expert Suggestions", action: #selector(showDebugExpertSuggestions), keyEquivalent: "")
            menu.addItem(debugShowExpertsItem)

            let debugClearExpertsItem = NSMenuItem(title: "Clear Debug Suggestions", action: #selector(clearDebugExpertSuggestions), keyEquivalent: "")
            menu.addItem(debugClearExpertsItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let installUpdateItem = NSMenuItem(title: "Install Available Update…", action: #selector(installPendingUpdate), keyEquivalent: "")
        installUpdateItem.isHidden = true
        installUpdateItem.target = self
        menu.addItem(installUpdateItem)
        self.installUpdateItem = installUpdateItem

        menu.addItem(NSMenuItem.separator())

        // Live as of v0.1.12 — Sparkle auto-checks on launch + every 24h,
        // and this menu item lets users trigger a manual check.
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        // Stash the menu rather than assigning statusItem.menu, so the
        // button's click action keeps firing. Right-click pops it manually
        // (see statusItemClicked).
        statusMenu = menu
    }

    /// Status-item button click handler. Fires on mouse-down of both
    /// buttons (see sendAction(on:) in setupMenuBar).
    ///   • right-click (or Control-click) → pop the classic NSMenu.
    ///   • left-click → toggle the menubar chat popover.
    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseDown
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick, let menu = statusMenu, let statusItem {
            // popUpMenu(_:) is deprecated but still the supported way to
            // show a status-item menu on demand without permanently
            // binding it via statusItem.menu. Assign-show-clear keeps the
            // left-click action intact for subsequent clicks.
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
            return
        }

        chatPopoverController?.toggle(relativeTo: sender)
    }

    // MARK: - Menu Actions

    @objc func switchTheme(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx < PopoverTheme.allThemes.count else { return }
        PopoverTheme.current = PopoverTheme.allThemes[idx]

        if let themeMenu = sender.menu {
            for item in themeMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }

        rebuildOpenPopovers()
    }

    @objc func switchDisplay(_ sender: NSMenuItem) {
        let idx = sender.tag
        controller?.pinnedScreenIndex = idx

        if let displayMenu = sender.menu {
            for item in displayMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }
    }

    // toggleChar1 (sprite show/hide) removed in phase 2 — no visible sprite.

    @objc func backToCharacter() {
        controller?.returnToGenie()
    }

    @objc func toggleDebug(_ sender: NSMenuItem) {
        guard let debugWin = controller?.debugWindow else { return }
        if debugWin.isVisible {
            debugWin.orderOut(nil)
            sender.state = .off
        } else {
            debugWin.orderFrontRegardless()
            sender.state = .on
        }
    }

    @objc func showDebugExpertSuggestions() {
        guard let controller, let char = controller.characters.first else { return }

        if controller.focusedExpert != nil {
            controller.focus(on: nil)
        }
        if !char.isIdleForPopover {
            char.openPopover()
        }

        let experts = controller.debugExpertSuggestions()
        char.terminalView?.setExpertSuggestions(experts)
        char.updatePopoverPosition()
        char.popoverWindow?.orderFrontRegardless()
        char.popoverWindow?.makeKey()
        if let terminal = char.terminalView {
            char.popoverWindow?.makeFirstResponder(terminal.inputField)
        }
    }

    @objc func clearDebugExpertSuggestions() {
        guard let controller, let char = controller.characters.first else { return }
        controller.clearDebugExpertSuggestions()
        char.terminalView?.hideExpertSuggestions()
    }

    @objc func toggleSounds(_ sender: NSMenuItem) {
        WalkerCharacter.soundsEnabled.toggle()
        sender.state = WalkerCharacter.soundsEnabled ? .on : .off
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            // Size the window to SettingsView's declared minimum
            // (840×620 in SettingsView.body's .frame). The window was
            // previously created at 600×460 — well below that minimum —
            // which crushed the NavigationSplitView: the sidebar (min
            // 220pt) plus the detail column couldn't fit, and the detail
            // pane's "Models" title + subtitle collided with the toolbar /
            // sidebar-toggle at the top-left. Matching the intended size
            // gives the split view room to lay out cleanly.
            let initialSize = NSSize(width: 920, height: 700)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Orion Settings"
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 11)
            window.collectionBehavior = [.canJoinAllSpaces]
            let hostingController = NSHostingController(rootView: SettingsView())
            window.contentViewController = hostingController
            window.setContentSize(initialSize)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc func installPendingUpdate() {
        pendingScheduledUpdate = false
        refreshPendingUpdateMenuItem()
        updaterController.checkForUpdates(nil)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Post-update Gatekeeper help

    /// macOS re-quarantines an unsigned .app every time Sparkle replaces
    /// it. Without enrolling in the Apple Developer Program (and adding
    /// codesign + notarytool to CI), the user has to run the xattr
    /// command after every update or face the "can't be opened because
    /// Apple cannot check it" Gatekeeper dialog.
    ///
    /// This helper detects "the app version changed since last launch"
    /// (likely an auto-update via Sparkle) and pops a dialog with the
    /// command pre-loaded plus a one-click "Copy & open Terminal"
    /// shortcut. Skipped on first install and when the version hasn't
    /// changed (normal launches).
    private static let lastLaunchedVersionKey = "lastLaunchedShortVersion"

    func checkForPostUpdateGatekeeperHelp() {
        let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        guard !currentVersion.isEmpty else { return }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: AppDelegate.lastLaunchedVersionKey)
        defaults.set(currentVersion, forKey: AppDelegate.lastLaunchedVersionKey)

        // First install (no previous record) → don't fire. Same version
        // → don't fire. Different version → fire.
        guard let last, last != currentVersion else { return }

        showPostUpdateGatekeeperHelpDialog(previous: last, current: currentVersion)
    }

    private func showPostUpdateGatekeeperHelpDialog(previous: String, current: String) {
        let command = "xattr -dr com.apple.quarantine /Applications/Orion.app"

        let alert = NSAlert()
        alert.messageText = "Orion updated to \(current)"
        alert.informativeText = """
            macOS may quarantine the new build the first time it relaunches and refuse to open it (you'll see "Orion can't be opened because Apple cannot check it for malicious software" or similar).

            Run this command in Terminal once to allow it through:

            \(command)

            Click 'Copy & open Terminal' to copy the command and launch Terminal in one go — paste with ⌘V and hit Return.
            """
        alert.alertStyle = .informational
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }
        alert.addButton(withTitle: "Copy & open Terminal")
        alert.addButton(withTitle: "Copy command")
        alert.addButton(withTitle: "Dismiss")

        // Make the alert appear above the dock and any popover.
        if let window = alert.window as? NSPanel {
            window.level = .floating
        }
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Copy + open Terminal
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(command, forType: .string)
            let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open(terminalURL)
        case .alertSecondButtonReturn:
            // Copy only
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(command, forType: .string)
        default:
            break
        }
    }
}

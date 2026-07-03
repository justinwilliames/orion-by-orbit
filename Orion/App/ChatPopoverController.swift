import AppKit

/// Lightweight owner of the menubar-summoned chat popover.
///
/// PHASE GOAL (additive): the existing walking sprite still owns and
/// fully wires the chat `NSWindow` + `TerminalView` + shared
/// `ClaudeSession` via `WalkerCharacter.openPopover()`. Rather than
/// duplicate that ~330-line window factory and ~200-line session wiring
/// (which are deeply coupled to the sprite — bubbles, live-status
/// fallbacks, completion sounds, expert tags), this controller REUSES
/// the sprite's proven popover machinery and simply re-anchors the
/// resulting window beneath the menubar status item.
///
/// Net effect for the user: clicking the menubar icon opens the SAME
/// chat surface, backed by the SAME shared `ClaudeSession` (no second
/// engine is spun up), positioned under the menubar instead of above the
/// sprite. The sprite's own click-to-chat path is untouched.
///
/// Why drive the sprite instead of building a parallel window:
///   • zero divergence — one window factory, one session wiring, one set
///     of callbacks. Bug fixes to the chat surface land in both places.
///   • the shared `ClaudeSession` is the character's `claudeSession`, so
///     conversation history is continuous whether summoned from the
///     sprite or the menubar.
///   • smallest possible compile surface under the no-Xcode constraint:
///     this file plus one additive flag (`isMenubarAnchored`) and one
///     guard in `updatePopoverPosition()`.
final class ChatPopoverController: NSObject {
    private weak var controller: LilAgentsController?

    /// Local event monitors installed while the menubar popover is open.
    /// The sprite's own monitors are suppressed for the duration (see
    /// `pinForMenubarSession`) because they close the popover whenever a
    /// click lands outside the *sprite* frame — which includes the
    /// menubar button itself.
    private var clickOutsideMonitor: Any?
    private var escapeKeyMonitor: Any?

    /// The status-bar button the popover is anchored to. Captured on
    /// toggle so repositioning + click-outside hit-testing can exclude
    /// the button's own region.
    private weak var anchorButton: NSStatusBarButton?

    init(controller: LilAgentsController?) {
        self.controller = controller
        super.init()
    }

    /// The single sprite character that owns the chat surface. Phase 1
    /// has exactly one character ("justin"); `characters.first` is it.
    private var character: WalkerCharacter? {
        controller?.characters.first
    }

    /// True when the menubar-anchored popover is currently on screen.
    private var isOpen: Bool {
        guard let character else { return false }
        return character.isMenubarAnchored
            && character.isIdleForPopover
            && (character.popoverWindow?.isVisible ?? false)
    }

    // MARK: - Public entry point

    /// Toggle the chat popover anchored under the menubar status item.
    /// Called from the status-item button's left-click action.
    func toggle(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        if isOpen {
            close()
        } else {
            open(relativeTo: button)
        }
    }

    // MARK: - Open / close

    private func open(relativeTo button: NSStatusBarButton) {
        guard let character else { return }

        // If the sprite's own (head-anchored) popover happens to be open,
        // close it first so we don't fight over the single window.
        if character.isIdleForPopover, !character.isMenubarAnchored {
            character.closePopover()
        }

        // Flag BEFORE openPopover so the very first updatePopoverPosition()
        // call inside openPopover() is skipped — we position manually.
        character.isMenubarAnchored = true

        // Suppress the sprite's frame-based click-outside monitors for the
        // duration of the menubar session. Pinning makes
        // refreshPopoverEventMonitors() early-return (installs nothing),
        // leaving click-outside / Escape entirely to this controller.
        character.isPopoverPinned = true

        // Reuse the sprite's proven popover lifecycle: builds the window +
        // TerminalView via createPopoverWindow(), reuses/starts the shared
        // ClaudeSession, wires every callback, restores transcript state,
        // and activates the app so keystrokes land in the input field.
        character.openPopover()

        // openPopover() ordered the window front above the sprite's head;
        // re-anchor it beneath the menubar button.
        position(relativeTo: button)

        installEventMonitors()
    }

    private func close() {
        guard let character else { return }

        removeEventMonitors()
        // Clear the menubar flag BEFORE closePopover() so the sprite's
        // normal position/idle lifecycle resumes cleanly next time.
        character.isMenubarAnchored = false
        character.isPopoverPinned = false
        character.closePopover()
    }

    // MARK: - Positioning

    /// Place the popover window just below the menubar status item,
    /// horizontally centered on the button, clamped to the menubar
    /// screen's visible frame.
    private func position(relativeTo button: NSStatusBarButton) {
        guard let character,
              let popover = character.popoverWindow,
              let buttonWindow = button.window else { return }
        // The status item lives on whichever screen carries the menubar
        // the button was clicked on.
        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? buttonWindow.frame

        // Button frame in screen coordinates.
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)

        let popoverSize = popover.frame.size
        // The bubble's tail (beak) juts UP out of the top `popoverTailHeight`
        // pixels of the window toward the menubar icon. Keep the gap tight so
        // the beak's apex lands just under the status item.
        let gap: CGFloat = 2

        // Center the popover horizontally under the button.
        var x = buttonRectOnScreen.midX - popoverSize.width / 2
        // Window is borderless with origin at bottom-left; place its TOP
        // (where the upward beak apex sits) just below the button's bottom
        // edge.
        var y = buttonRectOnScreen.minY - gap - popoverSize.height

        // Clamp onto the visible frame so the popover never spills off the
        // screen edges.
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - popoverSize.width - 4))
        y = max(visibleFrame.minY + 4, min(y, visibleFrame.maxY - popoverSize.height - 4))

        popover.setFrameOrigin(NSPoint(x: x, y: y))

        // The bubble outline's upward beak defaults to the popover's
        // horizontal centre. After the x-clamp above the popover may be
        // bumped sideways to fit on-screen, so re-point the beak at the
        // button's actual centre relative to the (now final) popover origin.
        let beakX = buttonRectOnScreen.midX - popover.frame.minX
        character.rebuildPopoverBubbleShellPath(
            forSize: popoverSize,
            tailCenterX: beakX,
            animated: false
        )
    }

    // MARK: - Event monitors (Escape + click-outside)

    private func installEventMonitors() {
        removeEventMonitors()

        // Click-outside: close unless the click is inside the popover, the
        // expert-switcher child popover, or on the menubar button itself
        // (so the toggle action can do its own open/close handling).
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, let character = self.character,
                  let popover = character.popoverWindow else { return }
            let mouse = NSEvent.mouseLocation

            if popover.frame.contains(mouse) { return }

            if let switcherFrame = character.expertSwitcherPopover?
                .contentViewController?.view.window?.frame,
               switcherFrame.contains(mouse) { return }

            if let button = self.anchorButton,
               let buttonWindow = button.window {
                let buttonRectInWindow = button.convert(button.bounds, to: nil)
                let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
                if buttonRectOnScreen.contains(mouse) { return }
            }

            self.close()
        }

        // Escape closes the popover (keyCode 53 == Escape). If the expert
        // switcher child popover is open, let its own Escape handling run
        // first by not intercepting.
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            if self?.character?.expertSwitcherPopover?.isShown == true {
                return event
            }
            self?.close()
            return nil
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
}

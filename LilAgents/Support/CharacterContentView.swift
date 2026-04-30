import AppKit

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class HoverTooltipController {
    static let shared = HoverTooltipController()

    private let window: NSPanel
    private let label: NSTextField
    private let padding = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

    private init() {
        window = NSPanel(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 20)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true

        let contentView = NSView(frame: .zero)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        contentView.layer?.cornerRadius = 10
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        window.contentView = contentView

        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        contentView.addSubview(label)
    }

    func show(_ text: String, from view: NSView) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parentWindow = view.window else { return }

        label.stringValue = trimmed
        label.sizeToFit()

        let width = label.frame.width + padding.left + padding.right
        let height = label.frame.height + padding.top + padding.bottom
        window.setContentSize(NSSize(width: width, height: height))
        label.frame = NSRect(
            x: padding.left,
            y: padding.bottom,
            width: width - padding.left - padding.right,
            height: height - padding.top - padding.bottom
        )

        let viewRectInWindow = view.convert(view.bounds, to: nil)
        let rectOnScreen = parentWindow.convertToScreen(viewRectInWindow)
        var x = rectOnScreen.midX - width / 2
        var y = rectOnScreen.maxY + 8

        if let screen = parentWindow.screen ?? NSScreen.main {
            x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - width - 8))
            if y + height > screen.visibleFrame.maxY - 8 {
                y = rectOnScreen.minY - height - 8
            }
        }

        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}

class CharacterContentView: NSView {
    weak var character: WalkerCharacter?
    private var mouseDownPoint: NSPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let character else { return nil }

        let menu = NSMenu()

        // ── Quick productivity tools ────────────────────────────────────
        let pomoItem = NSMenuItem(
            title: PomodoroController.shared.menuTitle,
            action: #selector(togglePomodoro),
            keyEquivalent: ""
        )
        pomoItem.target = self
        menu.addItem(pomoItem)

        let noteItem = NSMenuItem(title: "Quick note…", action: #selector(showQuickNote), keyEquivalent: "")
        noteItem.target = self
        menu.addItem(noteItem)

        let countItem = NSMenuItem(title: "Word + char count (clipboard)", action: #selector(showClipboardCount), keyEquivalent: "")
        countItem.target = self
        menu.addItem(countItem)

        let openItem = NSMenuItem(title: "Open ~/Orbit folder", action: #selector(openOrbitFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // ── Character behaviour ─────────────────────────────────────────
        let dontMoveItem = NSMenuItem(title: "Don't move", action: #selector(toggleMovementLocked(_:)), keyEquivalent: "")
        dontMoveItem.target = self
        dontMoveItem.state = character.movementLocked ? .on : .off
        menu.addItem(dontMoveItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
        settingsItem.target = NSApp.delegate
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Orion", action: #selector(AppDelegate.quitApp), keyEquivalent: "")
        quitItem.target = NSApp.delegate
        menu.addItem(quitItem)

        return menu
    }

    // MARK: Drag-and-drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Accept anything that the chat composer would accept — file URLs,
        // remote URLs, plain text, images. The composer's existing
        // attachment parser does the validation downstream.
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let character else { return false }
        // Open the chat popover (creating it if needed), then queue the
        // dropped attachments via the existing TerminalView pipeline so
        // they appear as chips in the composer. The user fills in their
        // question in the composer as normal.
        character.openPopover()
        DispatchQueue.main.async {
            guard let terminal = character.terminalView else { return }
            let attachments = terminal.attachments(from: sender.draggingPasteboard)
            terminal.queueAttachments(attachments)
        }
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // AVPlayerLayer is GPU-rendered so layer.render(in:) won't capture video pixels.
        // Use CGWindowListCreateImage to sample actual on-screen alpha at click point.
        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
        // Use the full virtual display height for the CG coordinate flip, not just
        // the main screen. NSScreen coordinates have origin at bottom-left of the
        // primary display, while CG uses top-left. The primary screen's height is
        // the correct basis for the flip across all monitors.
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let flippedY = primaryScreen.frame.height - screenPoint.y

        let captureRect = CGRect(x: screenPoint.x - 0.5, y: flippedY - 0.5, width: 1, height: 1)
        guard let windowID = window?.windowNumber, windowID > 0 else { return nil }

        if let image = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixel: [UInt8] = [0, 0, 0, 0]
            if let ctx = CGContext(
                data: &pixel, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if pixel[3] > 30 {
                    return self
                }
                return nil
            }
        }

        // Fallback: accept click if within center 60% of the view
        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.15
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        if let toolTip, !toolTip.isEmpty {
            HoverTooltipController.shared.show(toolTip, from: self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        HoverTooltipController.shared.hide()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        HoverTooltipController.shared.hide()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        if !didDrag, abs(currentPoint.x - mouseDownPoint.x) >= dragThreshold {
            didDrag = true
            character?.beginHorizontalDrag(at: event)
        }
        if didDrag {
            character?.continueHorizontalDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            character?.endHorizontalDrag()
        } else {
            character?.handleClick()
        }
        mouseDownPoint = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDownPoint = nil
        didDrag = false
        HoverTooltipController.shared.hide()
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    @objc private func toggleMovementLocked(_ sender: NSMenuItem) {
        guard let character else { return }
        character.setMovementLocked(!character.movementLocked)
    }

    // MARK: Quick-tool menu actions

    @objc private func togglePomodoro() {
        PomodoroController.shared.toggle()
    }

    @objc private func showQuickNote() {
        QuickNoteController.shared.show()
    }

    @objc private func showClipboardCount() {
        ClipboardCounter.showCount()
    }

    @objc private func openOrbitFolder() {
        OpenOrbitFolder.reveal()
    }
}

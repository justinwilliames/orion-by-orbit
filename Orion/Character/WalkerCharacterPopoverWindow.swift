import AppKit
import SwiftUI

private struct ExpertSwitcherEntry: Equatable {
    enum Destination: Equatable {
        case orion
        case expert(name: String, avatarPath: String)
    }

    let id: String
    let name: String
    let title: String?
    let avatarPath: String?
    let destination: Destination

    var searchIndex: String {
        "\(name) \(title ?? "")".lowercased()
    }

    var isJustin: Bool {
        if case .orion = destination { return true }
        return false
    }
}

private enum ExpertSwitcherCatalog {
    private static let lock = NSLock()
    private static var cachedEntries: [ExpertSwitcherEntry]?

    static func entries(using session: ClaudeSession) -> [ExpertSwitcherEntry] {
        lock.lock()
        if let cachedEntries {
            lock.unlock()
            return cachedEntries
        }
        lock.unlock()

        // Orion is single-persona: the guest-expert catalog (avatars, canonical
        // names, GuestTitles) was removed with the archive subsystem. The
        // switcher only ever offers the Orion row (its button is hidden +
        // disabled anyway — see createPopoverWindow()).
        _ = session
        let entries: [ExpertSwitcherEntry] = [
            ExpertSwitcherEntry(
                id: "orion",
                name: "Orbit",
                title: "your lifecycle assistant",
                avatarPath: nil,
                destination: .orion
            )
        ]

        lock.lock()
        cachedEntries = entries
        lock.unlock()
        return entries
    }
}

private final class ExpertSwitcherRowView: NSTableCellView {
    private let cardContainer = NSView()
    private let avatarContainer = NSView()
    private let avatarView = NSImageView()
    private let fallbackIcon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let checkmarkView = NSImageView()

    private var theme: PopoverTheme?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        cardContainer.layer?.cornerRadius = 16
    }

    func configure(entry: ExpertSwitcherEntry, theme: PopoverTheme, isCurrentSelection: Bool) {
        self.theme = theme
        wantsLayer = false
        cardContainer.layer?.borderWidth = 1
        cardContainer.layer?.backgroundColor = (isCurrentSelection ? theme.accentColor.withAlphaComponent(0.10) : theme.inputBg).cgColor
        cardContainer.layer?.borderColor = (isCurrentSelection ? theme.accentColor : theme.separatorColor.withAlphaComponent(0.52)).cgColor

        nameLabel.stringValue = entry.name
        nameLabel.textColor = theme.textPrimary

        let title = entry.title ?? ""
        titleLabel.stringValue = title
        titleLabel.isHidden = title.isEmpty
        titleLabel.textColor = isCurrentSelection ? theme.accentColor : theme.textDim

        avatarContainer.layer?.backgroundColor = theme.accentColor.withAlphaComponent(0.10).cgColor
        avatarContainer.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.40).cgColor

        if let avatarPath = entry.avatarPath,
           let image = resolvedAvatarImage(at: avatarPath) {
            avatarView.image = image
            avatarView.isHidden = false
            fallbackIcon.isHidden = true
        } else if entry.isJustin, let orbitLogo = NSImage(named: "OrbitLogo") {
            // Orion row → show the Orbit logo (bundled imageset, white
            // mark on transparent). Tinted with the theme accent so it picks
            // up the indigo brand colour against the row background.
            avatarView.image = nil
            avatarView.isHidden = true
            fallbackIcon.isHidden = false
            fallbackIcon.image = orbitLogo
            fallbackIcon.contentTintColor = theme.accentColor
        } else {
            avatarView.image = nil
            avatarView.isHidden = true
            fallbackIcon.isHidden = false
            if let fallback = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                fallbackIcon.image = fallback.withSymbolConfiguration(config)
            }
            fallbackIcon.contentTintColor = theme.accentColor
        }

        checkmarkView.isHidden = !isCurrentSelection
        checkmarkView.contentTintColor = theme.accentColor
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = false

        cardContainer.wantsLayer = true
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardContainer)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            cardContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            stack.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor)
        ])

        avatarContainer.wantsLayer = true
        avatarContainer.layer?.cornerRadius = 14
        avatarContainer.layer?.masksToBounds = true
        avatarContainer.layer?.borderWidth = 1
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.widthAnchor.constraint(equalToConstant: 28).isActive = true
        avatarContainer.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(avatarContainer)

        avatarView.imageScaling = .scaleAxesIndependently
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatarView)

        fallbackIcon.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(fallbackIcon)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),

            fallbackIcon.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            fallbackIcon.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            fallbackIcon.widthAnchor.constraint(equalToConstant: 16),
            fallbackIcon.heightAnchor.constraint(equalToConstant: 16)
        ])

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textStack)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(nameLabel)

        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)

        if let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            checkmarkView.image = checkmark.withSymbolConfiguration(config)
        }
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(checkmarkView)
    }
}

private final class ExpertSwitcherViewController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let theme: PopoverTheme
    private let entries: [ExpertSwitcherEntry]
    private let currentSelectionID: String
    private let onSelect: (ExpertSwitcherEntry) -> Void
    var onDismiss: (() -> Void)?

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyStateLabel = NSTextField(labelWithString: "No matches found.")
    private var filteredEntries: [ExpertSwitcherEntry] = []

    init(
        theme: PopoverTheme,
        entries: [ExpertSwitcherEntry],
        currentSelectionID: String,
        onSelect: @escaping (ExpertSwitcherEntry) -> Void
    ) {
        self.theme = theme
        self.entries = entries
        self.currentSelectionID = currentSelectionID
        self.onSelect = onSelect
        self.filteredEntries = entries
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let horizontalInset: CGFloat = 18
        let verticalInset: CGFloat = 14
        let contentGap: CGFloat = 12
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
        root.wantsLayer = true
        root.layer?.backgroundColor = theme.popoverBg.cgColor
        view = root

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search experts"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        root.addSubview(searchField)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        root.addSubview(scrollView)

        tableView.headerView = nil
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.rowHeight = 72
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(confirmSelection(_:))
        tableView.doubleAction = #selector(confirmSelection(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ExpertColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        emptyStateLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        emptyStateLabel.textColor = theme.textDim
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.isHidden = true
        root.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: verticalInset),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: horizontalInset),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -horizontalInset),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: contentGap),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -horizontalInset),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -verticalInset),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        reloadRows()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusSearchField()
        if let selectedIndex = filteredEntries.firstIndex(where: { $0.id == currentSelectionID }) {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDismiss?()
    }

    func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.searchField)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter { $0.searchIndex.contains(query) }
        }
        reloadRows()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)),
           tableView.numberOfRows > 0 {
            let selectedRow = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
            guard selectedRow < filteredEntries.count else { return true }
            onSelect(filteredEntries[selectedRow])
            return true
        }
        if commandSelector == #selector(moveDown(_:)), tableView.numberOfRows > 0 {
            let nextRow = min(max(tableView.selectedRow + 1, 0), tableView.numberOfRows - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(nextRow)
            return true
        }
        if commandSelector == #selector(moveUp(_:)), tableView.numberOfRows > 0 {
            let nextRow = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(nextRow)
            return true
        }
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        72
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row >= 0 && row < filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < filteredEntries.count else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("ExpertSwitcherRowView")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ExpertSwitcherRowView) ?? {
            let view = ExpertSwitcherRowView()
            view.identifier = identifier
            return view
        }()

        let entry = filteredEntries[row]
        cell.configure(entry: entry, theme: theme, isCurrentSelection: entry.id == currentSelectionID)
        return cell
    }

    @objc private func confirmSelection(_ sender: Any?) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < filteredEntries.count else { return }
        onSelect(filteredEntries[selectedRow])
    }

    private func reloadRows() {
        tableView.reloadData()
        if let selectedIndex = filteredEntries.firstIndex(where: { $0.id == currentSelectionID }) {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else if !filteredEntries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        emptyStateLabel.isHidden = !filteredEntries.isEmpty
    }
}

extension WalkerCharacter {
    var resolvedTheme: PopoverTheme {
        (themeOverride ?? PopoverTheme.current).withCharacterColor(characterColor).withCustomFont()
    }

    func refreshPopoverHeader() {
        popoverTitleLabel?.stringValue = focusedExpert?.name ?? resolvedTheme.titleString
        // Confident home header = icon badge + "Orbit" + actions. Only a
        // focused expert gets a subtitle; the Orbit home has none.
        popoverSubtitleLabel?.stringValue = focusedExpert?.title ?? ""
        popoverSubtitleLabel?.isHidden = (focusedExpert?.title == nil)
        popoverIconBadge?.isHidden = (focusedExpert != nil)
        popoverReturnButton?.isHidden = (focusedExpert == nil)
        terminalView?.setReturnToLennyVisible(focusedExpert != nil)
        updatePopoverExpertSwitcherState()
        updatePopoverTitleLayout()
    }

    func createPopoverWindow() {
        let t = resolvedTheme
        let popoverWidth: CGFloat = WalkerCharacter.defaultPopoverWidth                     // 468
        let totalHeight: CGFloat = WalkerCharacter.defaultPopoverHeight                      // 574
        let tailHeight: CGFloat = WalkerCharacter.popoverTailHeight                         //  14
        let tailWidth: CGFloat = WalkerCharacter.popoverTailWidth                           //  28
        let popoverHeight: CGFloat = totalHeight - tailHeight                               // 560 — body height
        let shellCornerRadius: CGFloat = 18

        let win = KeyableWindow(
            contentRect: CGRect(x: 0, y: 0, width: popoverWidth, height: totalHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let rgbPopoverBackground = t.rgbPopoverBackground
        let brightness = rgbPopoverBackground.redComponent * 0.299 + rgbPopoverBackground.greenComponent * 0.587 + rgbPopoverBackground.blueComponent * 0.114
        let isDark = brightness < 0.5
        win.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // Speech-bubble shell as a SINGLE continuous outline path.
        //
        // Earlier version drew the rounded body and the triangular tail as
        // two separate CAShapeLayers — visually correct individually, but
        // the body's stroked bottom edge plus the tail's stroked top base
        // stacked into a hairline seam exactly where they met. Now the
        // entire bubble (rounded rect + tail jut) is a single CGPath with
        // one fill and one stroke — no seam possible.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: totalHeight))
        host.wantsLayer = true
        host.autoresizingMask = [.width, .height]

        // Menubar-anchored popovers hang BELOW the status item at the top
        // of the screen, so the tail must point UP at the icon. The sprite
        // popover sits ABOVE the character, tail pointing down. One flag
        // (`isMenubarAnchored`, set before openPopover() calls this) picks
        // the geometry: tail-up + body at y=0, vs tail-down + body at
        // y=tailHeight.
        let tailOnTop = isMenubarAnchored
        let bodyOriginY: CGFloat = tailOnTop ? 0 : tailHeight

        let bubbleShape = CAShapeLayer()
        bubbleShape.frame = host.bounds
        bubbleShape.path = WalkerCharacter.bubbleShellPath(
            size: CGSize(width: popoverWidth, height: totalHeight),
            tailHeight: tailHeight,
            tailWidth: tailWidth,
            cornerRadius: shellCornerRadius,
            tailCenterX: tailCenterXRelativeToPopover(),
            tailOnTop: tailOnTop
        )
        bubbleShape.fillColor = t.popoverBg.cgColor
        bubbleShape.strokeColor = t.popoverBorder.cgColor
        bubbleShape.lineWidth = t.popoverBorderWidth
        bubbleShape.lineJoin = .round
        bubbleShape.shadowColor = NSColor.black.cgColor
        bubbleShape.shadowOpacity = 0.10
        bubbleShape.shadowRadius = 6
        bubbleShape.shadowOffset = CGSize(width: 0, height: -2)
        host.layer?.addSublayer(bubbleShape)
        popoverBubbleShape = bubbleShape

        // Body container — sits inside the bubble's body region (above the
        // tail strip) and clips inner subviews (terminal text, title bar,
        // controls) to the rounded body. Background and border are now
        // OWNED by `bubbleShape`; the container is a transparent overlay.
        // Springs-and-struts: top fixed at 0, bottom fixed at tailHeight,
        // height flexible — so the body grows when the popover expands.
        let container = NSView(frame: NSRect(x: 0, y: bodyOriginY, width: popoverWidth, height: popoverHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = shellCornerRadius
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]

        let titleBarHeight: CGFloat = 52
        let titleBar = NSView(frame: NSRect(x: 0, y: popoverHeight - titleBarHeight, width: popoverWidth, height: titleBarHeight))
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = t.titleBarBg.cgColor
        titleBar.layer?.cornerRadius = shellCornerRadius
        titleBar.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        titleBar.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleBar)

        let titleLabel = NSTextField(labelWithString: focusedExpert?.name ?? t.titleString)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // Wordmark in the theme title font (SF Pro Rounded semibold ≈ 15).
        titleLabel.font = t.titleFont
        titleLabel.textColor = t.titleText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        popoverTitleLabel = titleLabel

        // Expert switcher button — Orion is the only persona in
        // Orion, so the switcher dropdown has nothing meaningful to
        // offer. Created (so the rest of the layout maths still has the
        // reference) but hidden + disabled. Removing it entirely would
        // require rewiring layout constraints throughout the title bar.
        let switcherButton = HoverButton(title: "", target: self, action: #selector(toggleExpertSwitcher))
        switcherButton.translatesAutoresizingMaskIntoConstraints = false
        switcherButton.isBordered = false
        switcherButton.wantsLayer = true
        switcherButton.normalBg = NSColor.clear.cgColor
        switcherButton.hoverBg = NSColor.clear.cgColor
        switcherButton.layer?.backgroundColor = NSColor.clear.cgColor
        switcherButton.isHidden = true
        switcherButton.isEnabled = false
        popoverExpertSwitcherButton = switcherButton

        // Subtitle retained (an expert focus still shows a title) but the
        // default "Orbit's menu-bar assistant" clutters a confident header —
        // when there's no focused expert it stays empty. Header is just the
        // icon badge + "Orbit" wordmark + quiet actions.
        let subtitle = NSTextField(labelWithString: focusedExpert?.title ?? "")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = t.textDim.withAlphaComponent(0.75)
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.usesSingleLineMode = true
        subtitle.isHidden = (focusedExpert?.title == nil)
        popoverSubtitleLabel = subtitle

        let controlButtonSize: CGFloat = 28
        let buttonSpacing: CGFloat = 6
        // Title bar controls, right to left: close, then a tight
        // cluster of clear-conversation and settings. Expand and pin
        // were removed in v0.1.50 — Sir found them noisy and they
        // were a steady source of layout/state bugs (expand width
        // regressions, pin click-through quirks). The popover lives
        // at one fixed size now; close-and-reopen is the way back.
        let closeButtonX = popoverWidth - 12 - controlButtonSize
        let clearButtonX = closeButtonX - buttonSpacing - controlButtonSize
        let toolboxButtonX = clearButtonX - buttonSpacing - controlButtonSize
        let settingsButtonX = toolboxButtonX - buttonSpacing - controlButtonSize

        let settingsButton = HoverButton(title: "", target: NSApp.delegate, action: #selector(AppDelegate.openSettings))
        settingsButton.frame = NSRect(x: settingsButtonX, y: (titleBarHeight - controlButtonSize) / 2, width: controlButtonSize, height: controlButtonSize)
        // Right-edge anchored — keep glued to the title bar's right
        // edge when the popover expands (50% wider). Without this the
        // buttons stay at their original X positions, drift toward the
        // middle of the widened title bar, and the right edge is empty.
        settingsButton.autoresizingMask = .minXMargin
        settingsButton.isBordered = false
        settingsButton.wantsLayer = true
        settingsButton.normalBg = NSColor.clear.cgColor
        settingsButton.hoverBg = t.separatorColor.withAlphaComponent(0.16).cgColor
        settingsButton.layer?.backgroundColor = NSColor.clear.cgColor
        settingsButton.layer?.cornerRadius = controlButtonSize / 2
        if let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Open settings") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            settingsButton.image = image.withSymbolConfiguration(config)
        }
        settingsButton.imageScaling = .scaleProportionallyDown
        settingsButton.contentTintColor = t.textDim
        settingsButton.toolTip = "Open settings"
        titleBar.addSubview(settingsButton)
        popoverSettingsButton = settingsButton

        // Toolbox — popup menu for the productivity quick tools (start/
        // stop Pomodoro, new quick note, view past notes). Surfaced
        // here in the title bar so the actions are reachable from
        // inside the chat popover, not only via right-click on the
        // dock character.
        let toolboxButton = HoverButton(title: "", target: self, action: #selector(toolboxButtonTapped(_:)))
        toolboxButton.frame = NSRect(x: toolboxButtonX, y: (titleBarHeight - controlButtonSize) / 2, width: controlButtonSize, height: controlButtonSize)
        toolboxButton.autoresizingMask = .minXMargin
        toolboxButton.isBordered = false
        toolboxButton.wantsLayer = true
        toolboxButton.normalBg = NSColor.clear.cgColor
        toolboxButton.hoverBg = t.separatorColor.withAlphaComponent(0.16).cgColor
        toolboxButton.layer?.backgroundColor = NSColor.clear.cgColor
        toolboxButton.layer?.cornerRadius = controlButtonSize / 2
        if let image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Quick tools") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            toolboxButton.image = image.withSymbolConfiguration(config)
        }
        toolboxButton.imageScaling = .scaleProportionallyDown
        toolboxButton.contentTintColor = t.textDim
        toolboxButton.toolTip = "Quick tools"
        titleBar.addSubview(toolboxButton)
        popoverToolboxButton = toolboxButton

        let titleRowStack = NSStackView(views: [titleLabel, switcherButton])
        titleRowStack.translatesAutoresizingMaskIntoConstraints = false
        titleRowStack.orientation = .horizontal
        titleRowStack.alignment = .centerY
        titleRowStack.spacing = 8

        let titleTextStack = NSStackView(views: [titleRowStack, subtitle])
        titleTextStack.translatesAutoresizingMaskIntoConstraints = false
        titleTextStack.orientation = .vertical
        titleTextStack.alignment = .leading
        titleTextStack.spacing = 0
        titleTextStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // App-icon badge — the indigo Orbit squircle at ~25pt, drawn in a
        // rounded 8pt image view next to the wordmark. Only shown for the
        // Orbit home header (not when a specific expert is focused).
        let iconBadge = NSImageView()
        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        // The running app's icon = the indigo Orbit squircle. applicationIconName
        // is the reliable runtime handle (an .appiconset isn't loadable by its
        // catalog name); fall back to a named asset just in case.
        iconBadge.image = NSImage(named: NSImage.applicationIconName) ?? NSImage(named: "AppIcon")
        iconBadge.imageScaling = .scaleProportionallyUpOrDown
        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 9
        iconBadge.layer?.masksToBounds = true
        iconBadge.layer?.borderWidth = 1
        iconBadge.layer?.borderColor = t.textDim.withAlphaComponent(0.5).cgColor
        iconBadge.isHidden = (focusedExpert != nil)
        popoverIconBadge = iconBadge

        let headerStack = NSStackView(views: [iconBadge, titleTextStack])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 10
        headerStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleBar.addSubview(headerStack)

        let clearButton = HoverButton(title: "", target: self, action: #selector(clearConversationTapped))
        clearButton.frame = NSRect(x: clearButtonX, y: (titleBarHeight - controlButtonSize) / 2, width: controlButtonSize, height: controlButtonSize)
        clearButton.autoresizingMask = .minXMargin
        clearButton.isBordered = false
        clearButton.wantsLayer = true
        clearButton.normalBg = NSColor.clear.cgColor
        clearButton.hoverBg = t.separatorColor.withAlphaComponent(0.16).cgColor
        clearButton.layer?.backgroundColor = NSColor.clear.cgColor
        clearButton.layer?.cornerRadius = controlButtonSize / 2
        // Prefer the modern "new message" SF Symbol; fall back to the
        // older compose glyph; fall back again to a literal "+" title
        // so the button is never visually empty even if SF Symbols are
        // missing on the running macOS / theme combo.
        let clearSymbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let img = NSImage(systemSymbolName: "plus.message", accessibilityDescription: "New conversation") {
            clearButton.image = img.withSymbolConfiguration(clearSymbolConfig)
        } else if let img = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New conversation") {
            clearButton.image = img.withSymbolConfiguration(clearSymbolConfig)
        } else {
            clearButton.title = "+"
            clearButton.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        }
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.contentTintColor = t.textDim
        clearButton.toolTip = "Start a new conversation"
        titleBar.addSubview(clearButton)

        // Expand + pin buttons removed in v0.1.50 — popover is now
        // a single fixed size. Click-outside still closes; close
        // button still closes; that's the full lifecycle.

        let closeButton = HoverButton(title: "", target: self, action: #selector(closePopoverFromButton))
        closeButton.frame = NSRect(x: closeButtonX, y: (titleBarHeight - controlButtonSize) / 2, width: controlButtonSize, height: controlButtonSize)
        closeButton.autoresizingMask = .minXMargin
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.normalBg = NSColor.clear.cgColor
        closeButton.hoverBg = t.errorColor.withAlphaComponent(0.20).cgColor
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
        closeButton.layer?.cornerRadius = controlButtonSize / 2
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            closeButton.image = image.withSymbolConfiguration(config)
        }
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = t.textDim
        closeButton.toolTip = "Close"
        titleBar.addSubview(closeButton)
        popoverCloseButton = closeButton

        NSLayoutConstraint.activate([
            switcherButton.widthAnchor.constraint(equalToConstant: 18),
            switcherButton.heightAnchor.constraint(equalToConstant: 18),

            iconBadge.widthAnchor.constraint(equalToConstant: 38),
            iconBadge.heightAnchor.constraint(equalToConstant: 38),

            headerStack.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 18),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -12),
            headerStack.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor, constant: -1)
        ])

        let returnPill = HoverButton(title: "", target: self, action: #selector(returnToGenieTapped))
        let returnPillWidth: CGFloat = 118
        returnPill.frame = NSRect(x: settingsButtonX - 8 - returnPillWidth, y: 14, width: returnPillWidth, height: 26)
        returnPill.autoresizingMask = .minXMargin
        returnPill.isBordered = false
        returnPill.wantsLayer = true
        returnPill.normalBg = t.inputBg.withAlphaComponent(0.90).cgColor
        returnPill.hoverBg = t.accentColor.withAlphaComponent(0.08).cgColor
        returnPill.layer?.backgroundColor = t.inputBg.withAlphaComponent(0.90).cgColor
        returnPill.layer?.cornerRadius = 13
        returnPill.layer?.borderWidth = 0.75
        returnPill.layer?.borderColor = t.separatorColor.withAlphaComponent(0.55).cgColor
        returnPill.attributedTitle = NSAttributedString(
            string: "Back to Orbit",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: t.accentColor
            ]
        )
        returnPill.toolTip = "Return to Orbit"
        returnPill.isHidden = true
        titleBar.addSubview(returnPill)
        popoverReturnButton = returnPill

        let sep = NSView(frame: NSRect(x: 0, y: popoverHeight - titleBarHeight - 1, width: popoverWidth, height: 0.5))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = t.separatorColor.withAlphaComponent(0.30).cgColor
        sep.autoresizingMask = [.width, .minYMargin]
        container.addSubview(sep)

        let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: popoverHeight - titleBarHeight - 1))
        terminal.characterColor = characterColor
        terminal.themeOverride = themeOverride
        terminal.autoresizingMask = [.width, .height]
        terminal.isPinnedOpen = isPopoverPinned
        terminal.onSendMessage = { [weak self] message, attachments in
            self?.noteLiveStatusEvent()
            self?.setCurrentActivityStatus("Getting things moving…")
            self?.updateExpertNameTag()
            self?.claudeSession?.focusedExpert = self?.focusedExpert
            self?.claudeSession?.send(message: message, attachments: attachments)
        }
        terminal.onStopRequested = { [weak self] in
            guard let self else { return }
            self.claudeSession?.cancelActiveTurn()
            self.stopLiveStatusFallback()
            self.setCurrentActivityStatus("")
            self.terminalView?.endStreaming()
            self.terminalView?.clearLiveStatus()
            self.updateExpertNameTag()
        }
        terminal.onReturnToLenny = { [weak self] in
            self?.controller?.returnToGenie()
        }
        terminal.onSelectExpert = { [weak self] expert in
            self?.controller?.focus(on: expert)
        }
        terminal.onSelectExpertSuggestion = { [weak self] entryID, expert in
            guard let self else { return }
            self.claudeSession?.collapseExpertSuggestionEntry(entryID, pickedExpert: expert, for: self.focusedExpert)
            self.controller?.focus(on: expert)
        }
        terminal.onEditExpertSuggestion = { [weak self] entryID in
            guard let self else { return }
            self.claudeSession?.expandExpertSuggestionEntry(entryID, for: self.focusedExpert)
            self.restoreTranscriptState()
        }
        terminal.onTogglePinned = { [weak self] in
            self?.togglePopoverPinned()
        }
        terminal.onCloseRequested = { [weak self] in
            self?.closePopoverFromButton()
        }
        terminal.onRefreshSetupState = { [weak self] in
            guard let self, let session = self.claudeSession, !session.isRunning else { return }
            session.focusedExpert = self.focusedExpert
            session.start()
        }
        terminal.onReachedTranscriptBottom = { [weak self] in
            guard let self else { return }
            self.claudeSession?.markConversationRead(for: self.focusedExpert)
        }
        terminal.setReturnToLennyVisible(focusedExpert != nil)
        container.addSubview(terminal)

        host.addSubview(container)
        win.contentView = host
        popoverWindow = win
        terminalView = terminal
        refreshPopoverHeader()
        syncPopoverPinState()

        let session = claudeSession ?? ClaudeSession()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ExpertSwitcherCatalog.entries(using: session)
        }
    }

    /// Toolbox button → toggle the in-popover SwiftUI overlay covering
    /// the chat surface. Rebuilds chrome on close. No menu navigation.
    @objc func toolboxButtonTapped(_ sender: NSButton) {
        if let overlay = popoverToolboxOverlay, !overlay.isHidden {
            hideToolboxOverlay()
        } else {
            showToolboxOverlay()
        }
    }

    private func showToolboxOverlay() {
        guard let popoverWindow,
              let container = popoverWindow.contentView else { return }

        let overlay: NSView
        if let existing = popoverToolboxOverlay {
            overlay = existing
            overlay.isHidden = false
        } else {
            // Title bar is 52pt; the overlay covers everything below it.
            let titleBarHeight: CGFloat = 52
            let frame = NSRect(
                x: 0,
                y: 0,
                width: container.bounds.width,
                height: container.bounds.height - titleBarHeight
            )
            let hosting = NSHostingView(rootView: ToolboxRootView(onClose: { [weak self] in
                self?.hideToolboxOverlay()
            }))
            hosting.frame = frame
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting, positioned: .above, relativeTo: nil)
            popoverToolboxOverlay = hosting
            overlay = hosting
        }
        // Re-create the SwiftUI root each show so transient state
        // (selection, drafts) starts fresh and live properties (Pomodoro
        // phase) reflect current values rather than stale captures.
        if let hosting = overlay as? NSHostingView<ToolboxRootView> {
            hosting.rootView = ToolboxRootView(onClose: { [weak self] in
                self?.hideToolboxOverlay()
            })
        }
        overlay.needsDisplay = true
    }

    private func hideToolboxOverlay() {
        popoverToolboxOverlay?.isHidden = true
    }

    @objc func toggleExpertSwitcher() {
        guard let anchorButton = popoverExpertSwitcherButton else { return }

        if let popover = expertSwitcherPopover, popover.isShown {
            popover.performClose(nil)
            updatePopoverExpertSwitcherState()
            return
        }

        let entries = availableExpertSwitcherEntries()
        guard !entries.isEmpty else { return }

        let currentSelectionID = focusedExpert.map { "expert:\($0.name)" } ?? "orion"
        let controller = ExpertSwitcherViewController(
            theme: resolvedTheme,
            entries: entries,
            currentSelectionID: currentSelectionID
        ) { [weak self] entry in
            guard let self else { return }
            self.expertSwitcherPopover?.performClose(nil)
            self.updatePopoverExpertSwitcherState()
            WalkerCharacter.playSelectionSound()

            switch entry.destination {
            case .orion:
                guard self.focusedExpert != nil else { return }
                self.controller?.returnToGenie()
            case .expert(let name, let avatarPath):
                // Orion is single-persona: the expert catalog was removed, so
                // the switcher never surfaces expert entries. This branch is
                // unreachable, but we build a bare ResponderExpert (no
                // GuestTitles / archive context) to keep the switch exhaustive.
                if let focusedExpert = self.focusedExpert, focusedExpert.name == name {
                    return
                }
                let expert = ResponderExpert(
                    name: name,
                    avatarPath: avatarPath,
                    archiveContext: "",
                    responseScript: ""
                )
                self.controller?.focus(on: expert)
            }
        }
        controller.onDismiss = { [weak self] in
            self?.updatePopoverExpertSwitcherState()
        }

        let popover = expertSwitcherPopover ?? NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = controller
        expertSwitcherPopover = popover
        popover.show(relativeTo: anchorButton.bounds, of: anchorButton, preferredEdge: .maxY)
        controller.focusSearchField()
        updatePopoverExpertSwitcherState()
    }

    private func updatePopoverExpertSwitcherState() {
        guard let button = popoverExpertSwitcherButton else { return }
        let symbolName = expertSwitcherPopover?.isShown == true ? "chevron.up" : "chevron.down"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Switch conversation") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
        }

        let t = resolvedTheme
        let normal = expertSwitcherPopover?.isShown == true
            ? t.separatorColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        button.normalBg = normal
        button.layer?.backgroundColor = normal
        button.contentTintColor = expertSwitcherPopover?.isShown == true ? t.accentColor : t.textDim
    }

    private func updatePopoverTitleLayout() {
        popoverTitleLabel?.invalidateIntrinsicContentSize()
        popoverSubtitleLabel?.invalidateIntrinsicContentSize()
    }

    private func availableExpertSwitcherEntries() -> [ExpertSwitcherEntry] {
        let session = claudeSession ?? ClaudeSession()
        return ExpertSwitcherCatalog.entries(using: session)
    }
}

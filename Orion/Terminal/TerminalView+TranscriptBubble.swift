import AppKit

class ChatBubbleView: NSView, NSTextViewDelegate {
    let textView = NSTextView()
    let headerLabel = NSTextField(labelWithString: "")
    let headerTitleLabel = NSTextField(labelWithString: "")
    let bubbleBackground = NSView()
    let avatarContainer = NSView()
    let headerRow = NSStackView()
    let actionRow = NSStackView()
    private let contentColumn = NSStackView()
    private let copyButton = HoverButton(title: "", target: nil, action: nil)
    private let followUpButton = HoverButton(title: "", target: nil, action: nil)
    let isUser: Bool
    private let showsSpeakerHeader: Bool
    private let theme: PopoverTheme
    private let textInsets: NSSize
    var textWidthConstraint: NSLayoutConstraint?
    var textHeightConstraint: NSLayoutConstraint?
    var onCopy: (() -> Void)?
    var onFollowUp: (() -> Void)?
    /// Original markdown source for the bubble's contents. Carried so
    /// the copy button can produce a Slack-formatted version of the
    /// reply, not just the rendered plain text from `textView.string`.
    /// Updated by `setMarkdownSource(_:)` during streaming.
    var markdownSource: String?

    init(
        text: NSAttributedString,
        isUser: Bool,
        speaker: TranscriptSpeaker,
        theme: PopoverTheme,
        showsSpeakerHeader: Bool = true,
        textInsets: NSSize = NSSize(width: 14, height: 12),
        markdownSource: String? = nil,
        onCopy: (() -> Void)? = nil,
        onFollowUp: (() -> Void)? = nil
    ) {
        self.isUser = isUser
        self.showsSpeakerHeader = showsSpeakerHeader
        self.theme = theme
        self.textInsets = textInsets
        self.markdownSource = markdownSource
        self.onCopy = onCopy
        self.onFollowUp = onFollowUp
        super.init(frame: .zero)
        setupViews()
        populate(text: text, speaker: speaker)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        contentColumn.orientation = .vertical
        contentColumn.alignment = isUser ? .trailing : .leading
        contentColumn.spacing = showsSpeakerHeader ? 7 : 0
        contentColumn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentColumn)

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(headerRow)

        avatarContainer.wantsLayer = true
        avatarContainer.layer?.cornerRadius = 14
        avatarContainer.layer?.masksToBounds = true
        avatarContainer.layer?.borderWidth = 1
        avatarContainer.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.30).cgColor
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.widthAnchor.constraint(equalToConstant: isUser ? 0 : 28).isActive = true
        avatarContainer.heightAnchor.constraint(equalToConstant: isUser ? 0 : 28).isActive = true
        avatarContainer.isHidden = isUser
        headerRow.addArrangedSubview(avatarContainer)

        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = isUser ? theme.textDim : theme.accentColor
        headerLabel.alignment = .left
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.isEditable = false
        headerLabel.isBordered = false
        headerLabel.drawsBackground = false
        headerRow.addArrangedSubview(headerLabel)

        headerTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        headerTitleLabel.textColor = theme.textDim
        headerTitleLabel.alignment = .left
        headerTitleLabel.lineBreakMode = .byTruncatingTail
        headerTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerTitleLabel.isEditable = false
        headerTitleLabel.isBordered = false
        headerTitleLabel.drawsBackground = false
        headerTitleLabel.isHidden = true
        headerRow.addArrangedSubview(headerTitleLabel)

        bubbleBackground.wantsLayer = true
        bubbleBackground.layer?.cornerRadius = theme.bubbleCornerRadius
        bubbleBackground.layer?.backgroundColor = isUser
            ? theme.accentColor.withAlphaComponent(0.10).cgColor
            : theme.bubbleBg.cgColor
        bubbleBackground.layer?.borderWidth = isUser ? 0 : 0.75
        bubbleBackground.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.36).cgColor
        bubbleBackground.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(bubbleBackground)

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = textInsets
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: theme.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.paragraphSpacing = 7
        p.alignment = .left
        textView.defaultParagraphStyle = p
        bubbleBackground.addSubview(textView)

        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 4
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(actionRow)

        var constraints = [
            contentColumn.topAnchor.constraint(equalTo: topAnchor),
            contentColumn.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentColumn.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentColumn.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: bubbleBackground.topAnchor),
            textView.bottomAnchor.constraint(equalTo: bubbleBackground.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: bubbleBackground.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: bubbleBackground.trailingAnchor),
        ]

        if isUser {
            // 12pt right margin so user bubbles have visible
            // breathing room from the popover's right edge — was 0pt
            // historically, which made wrapped lines like "actually
            // works" look clipped against the bubble shell.
            constraints.append(bubbleBackground.leadingAnchor.constraint(greaterThanOrEqualTo: contentColumn.leadingAnchor, constant: 56))
            constraints.append(bubbleBackground.trailingAnchor.constraint(equalTo: contentColumn.trailingAnchor, constant: -12))
        } else {
            constraints.append(bubbleBackground.leadingAnchor.constraint(equalTo: contentColumn.leadingAnchor))
            constraints.append(bubbleBackground.trailingAnchor.constraint(lessThanOrEqualTo: contentColumn.trailingAnchor, constant: -56))
        }

        NSLayoutConstraint.activate(constraints)

        contentColumn.setContentHuggingPriority(.required, for: .vertical)
        contentColumn.setContentCompressionResistancePriority(.required, for: .vertical)
        bubbleBackground.setContentHuggingPriority(.required, for: .vertical)
        bubbleBackground.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func configureCopyAction(_ button: HoverButton, action: Selector) {
        button.isBordered = false
        button.wantsLayer = true
        button.normalBg = .clear
        button.hoverBg = theme.accentColor.withAlphaComponent(0.10).cgColor
        button.layer?.backgroundColor = .clear
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 0
        button.contentTintColor = theme.textDim
        if let image = NSImage(systemSymbolName: "document.on.document", accessibilityDescription: "Copy message") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 16).isActive = true
        button.heightAnchor.constraint(equalToConstant: 16).isActive = true
    }

    private func configureFollowUpAction(_ button: HoverButton, action: Selector) {
        button.isBordered = false
        button.wantsLayer = true
        button.normalBg = theme.inputBg.cgColor
        button.hoverBg = theme.accentColor.withAlphaComponent(0.08).cgColor
        button.layer?.backgroundColor = button.normalBg
        button.layer?.cornerRadius = 15
        button.layer?.borderWidth = 1
        button.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.40).cgColor
        button.contentTintColor = theme.textPrimary
        button.attributedTitle = NSAttributedString(string: "Ask follow-up", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: theme.textPrimary
        ])
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 124).isActive = true
    }

    private func populate(text: NSAttributedString, speaker: TranscriptSpeaker) {
        headerLabel.stringValue = speaker.name
        if let title = speaker.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            headerTitleLabel.stringValue = "(\(title))"
            headerTitleLabel.isHidden = false
        } else {
            headerTitleLabel.stringValue = ""
            headerTitleLabel.isHidden = true
        }
        populateAvatar(for: speaker)
        configureHeaderVisibility()
        configureTextContainer()
        textView.textStorage?.setAttributedString(text)
        updateTextAlignment()
        configureActions(for: speaker)
        recalculateSize()
    }

    private func configureHeaderVisibility() {
        if showsSpeakerHeader {
            if headerRow.superview == nil {
                contentColumn.insertArrangedSubview(headerRow, at: 0)
            }
        } else if headerRow.superview != nil {
            contentColumn.removeArrangedSubview(headerRow)
            headerRow.removeFromSuperview()
        }
    }

    private func populateAvatar(for speaker: TranscriptSpeaker) {
        avatarContainer.subviews.forEach { $0.removeFromSuperview() }
        guard !isUser else { return }

        let image: NSImage?
        if let avatarPath = speaker.avatarPath {
            image = resolvedAvatarImage(at: avatarPath)
        } else if speaker.kind == .orion {
            image = resolvedLennyAvatarImage()
        } else {
            image = nil
        }

        if let image {
            let avatarView = NSImageView()
            avatarView.image = image
            avatarView.imageScaling = .scaleProportionallyUpOrDown
            avatarView.imageAlignment = .alignCenter
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            avatarContainer.addSubview(avatarView)
            NSLayoutConstraint.activate([
                avatarView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
                avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
                avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
                avatarView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor)
            ])
            return
        }

        let icon = NSImageView()
        let symbolName = speaker.kind == .orion ? "sparkles" : "person.crop.circle.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            icon.image = image.withSymbolConfiguration(config)
        }
        icon.contentTintColor = theme.accentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15)
        ])
    }

    private func configureActions(for speaker: TranscriptSpeaker) {
        actionRow.arrangedSubviews.forEach {
            actionRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // Show copy button for both .orion (Orion himself) and
        // .expert speakers. Originally upstream gated on .expert only —
        // Orion's own replies were never copyable, which silently
        // killed the most common copy case for users.
        if (speaker.kind == .orion || speaker.kind == .expert), onCopy != nil {
            configureCopyAction(copyButton, action: #selector(copyTapped))
            actionRow.addArrangedSubview(copyButton)
        }

        if speaker.kind == .expert, onFollowUp != nil {
            configureFollowUpAction(followUpButton, action: #selector(followUpTapped))
            actionRow.addArrangedSubview(followUpButton)
        }

        if actionRow.arrangedSubviews.isEmpty {
            contentColumn.removeArrangedSubview(actionRow)
            actionRow.removeFromSuperview()
        } else if actionRow.superview == nil {
            contentColumn.addArrangedSubview(actionRow)
        }
    }

    /// Maximum width the bubble's text column should occupy, set by
    /// the parent `TerminalView` after each layout pass. Setting this
    /// triggers a `recalculateSize()` so the bubble responds when the
    /// popover toggles between default and expanded modes. Default
    /// stays at 380 for the initial render before the parent has
    /// computed the column width.
    var maxBubbleWidth: CGFloat = 380 {
        didSet {
            guard oldValue != maxBubbleWidth else { return }
            recalculateSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        let fitting = contentColumn.fittingSize
        return NSSize(width: NSView.noIntrinsicMetric, height: fitting.height)
    }
}

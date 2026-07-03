import AppKit

/// Welcome-panel card that nudges first-launch users to fill out the
/// business-context survey. Mirrors the layout of `ConnectionSetupCardView`
/// so the popover stays visually consistent.
///
/// Two actions:
///   - "Set up" → opens Settings to the Business Context pane
///   - "Skip for now" → stamps the prompt as shown for this app version,
///     so the card stays dismissed until the next update
class BusinessContextPromptCardView: NSView {
    var onSetupTapped: (() -> Void)?
    var onSkipTapped: (() -> Void)?

    private let theme: PopoverTheme

    init(theme: PopoverTheme) {
        self.theme = theme
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.inputBg.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = theme.separatorColor.withAlphaComponent(0.45).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        let title = NSTextField(wrappingLabelWithString: "Sharper answers in 90 seconds")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = theme.textPrimary
        title.maximumNumberOfLines = 0
        stack.addArrangedSubview(title)
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let body = NSTextField(wrappingLabelWithString: "Tell me about your program — vertical, ESP, list size, current pain. Stays on your Mac. No customer data. I'll use it to skip beginner framing and reach for ESP-specific examples.")
        body.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        body.textColor = theme.textDim
        body.maximumNumberOfLines = 0
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(actionRow)
        actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let setupButton = HoverButton(title: "", target: self, action: #selector(setupTapped))
        setupButton.isBordered = false
        setupButton.wantsLayer = true
        setupButton.normalBg = theme.accentColor.cgColor
        setupButton.hoverBg = theme.accentColor.withAlphaComponent(0.82).cgColor
        setupButton.layer?.backgroundColor = setupButton.normalBg
        setupButton.layer?.cornerRadius = 12
        setupButton.horizontalContentPadding = 14
        setupButton.verticalContentPadding = 6
        setupButton.attributedTitle = NSAttributedString(string: "Set up", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        setupButton.translatesAutoresizingMaskIntoConstraints = false
        setupButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        actionRow.addArrangedSubview(setupButton)

        let skipButton = HoverButton(title: "", target: self, action: #selector(skipTapped))
        skipButton.isBordered = false
        skipButton.wantsLayer = true
        skipButton.normalBg = .clear
        skipButton.hoverBg = theme.separatorColor.withAlphaComponent(0.10).cgColor
        skipButton.layer?.backgroundColor = .clear
        skipButton.layer?.cornerRadius = 8
        skipButton.horizontalContentPadding = 8
        skipButton.verticalContentPadding = 4
        skipButton.attributedTitle = NSAttributedString(string: "Skip for now", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: theme.textDim
        ])
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        actionRow.addArrangedSubview(skipButton)

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @objc private func setupTapped() {
        onSetupTapped?()
    }

    @objc private func skipTapped() {
        onSkipTapped?()
    }
}

import AppKit

// MARK: - Starter Pack upsell card

class StarterPackUpsellCardView: NSView {
    var onConnectTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?
    var onSkipTapped: (() -> Void)?

    private let theme: PopoverTheme
    private let compact: Bool
    private let showsSkipButton: Bool

    init(theme: PopoverTheme, compact: Bool = false, showsSkipButton: Bool = false) {
        self.theme = theme
        self.compact = compact
        self.showsSkipButton = showsSkipButton
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.inputBg.cgColor
        layer?.cornerRadius = compact ? 12 : 16
        layer?.borderWidth = 1
        layer?.borderColor = theme.separatorColor.withAlphaComponent(0.45).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = compact ? 8 : 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let horizontalInset: CGFloat = 14
        let verticalInset: CGFloat = compact ? 12 : 16
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(compact ? 12 : 14))
        ])

        if !compact {
            let eyebrow = NSTextField(labelWithString: "Starter Pack")
            eyebrow.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            eyebrow.textColor = theme.accentColor
            stack.addArrangedSubview(eyebrow)
        }

        let title = NSTextField(wrappingLabelWithString: compact ? "Unlock the full archive" : "Get the full archive")
        title.font = NSFont.systemFont(ofSize: compact ? 13 : 14, weight: .semibold)
        title.textColor = theme.textPrimary
        title.maximumNumberOfLines = 0
        stack.addArrangedSubview(title)
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let body = NSTextField(wrappingLabelWithString: compact
            ? "Connect a model provider to start chatting."
            : "Your starter pack covers the essentials. Connect a model provider in Settings."
        )
        body.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        body.textColor = theme.textDim
        body.maximumNumberOfLines = 0
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonRow)

        let connectButton = makePrimaryButton(title: "Connect official MCP", action: #selector(connectTapped))
        buttonRow.addArrangedSubview(connectButton)

        if showsSkipButton {
            let skipButton = makeSecondaryButton(title: "Skip for now", action: #selector(skipTapped))
            buttonRow.addArrangedSubview(skipButton)
        } else if !compact {
            let settingsButton = makeSecondaryButton(title: "Open Settings", action: #selector(settingsTapped))
            buttonRow.addArrangedSubview(settingsButton)
        }

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func makePrimaryButton(title: String, action: Selector) -> HoverButton {
        let button = HoverButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.normalBg = theme.accentColor.cgColor
        button.hoverBg = theme.accentColor.withAlphaComponent(0.82).cgColor
        button.layer?.backgroundColor = button.normalBg
        button.layer?.cornerRadius = 12
        button.horizontalContentPadding = 16
        button.verticalContentPadding = 6
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        button.contentTintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func makeSecondaryButton(title: String, action: Selector) -> HoverButton {
        let button = HoverButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.normalBg = theme.bubbleBg.cgColor
        button.hoverBg = theme.accentColor.withAlphaComponent(0.08).cgColor
        button.layer?.backgroundColor = button.normalBg
        button.layer?.cornerRadius = 12
        button.layer?.borderWidth = 1
        button.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.42).cgColor
        button.horizontalContentPadding = 14
        button.verticalContentPadding = 6
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: theme.textPrimary
        ])
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    @objc private func connectTapped() { onConnectTapped?() }
    @objc private func settingsTapped() { onSettingsTapped?() }
    @objc private func skipTapped() { onSkipTapped?() }
}

// MARK: - MCP upsell card (rides under a completed answer)

/// Small, dismissible card rendered UNDER a completed assistant answer
/// (see TerminalView+TranscriptBehavior.endStreaming()). Points to the
/// paid Orbit MCP for the three moments where the free Mac app hits its
/// ceiling: BUILD (Claude can produce the artifact), DEEP-WORK (the
/// whole workflow, not one answer), and LIMIT (past what this app can
/// reach at all — no live Braze, no files, no end-to-end runs).
///
/// Never gates or delays the answer above it — by construction this
/// view is only ever appended after streaming finishes.
class MCPUpsellCardView: NSView {
    var onCTATapped: (() -> Void)?
    var onNotNowTapped: (() -> Void)?

    private let theme: PopoverTheme
    private let moment: MCPUpsellMoment

    /// Verbatim SET B copy (rename-and-upsell-strings.md). Never
    /// paraphrase — this copy went through a voice pass.
    private var headline: String {
        switch moment {
        case .build: return "I can explain it. Claude can build it."
        case .deepWork: return "This is a whole workflow."
        case .limit: return "This is past what I can reach."
        }
    }

    private var body: String {
        switch moment {
        case .build:
            return "That's a make-something question — an email, a template, subject lines. With the Orbit MCP, Claude produces the artifact instead of the instructions."
        case .deepWork:
            return "Audits, win-back programs, pre-launch QA — that's discovery, build, and check end to end. The Orbit MCP runs the sequence inside Claude, not one answer at a time."
        case .limit:
            return "I can't connect to your live Braze, generate files, or run end-to-end workflows. The Orbit MCP inside Claude Desktop does all three."
        }
    }

    init(theme: PopoverTheme, moment: MCPUpsellMoment) {
        self.theme = theme
        self.moment = moment
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.inputBg.cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = theme.separatorColor.withAlphaComponent(0.45).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        let eyebrow = NSTextField(labelWithString: "Orbit MCP")
        eyebrow.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        eyebrow.textColor = theme.accentColor
        stack.addArrangedSubview(eyebrow)

        let titleLabel = NSTextField(wrappingLabelWithString: headline)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = theme.textPrimary
        titleLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        bodyLabel.textColor = theme.textDim
        bodyLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(bodyLabel)
        bodyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonRow)

        let ctaButton = makePrimaryButton(title: "See the MCP", action: #selector(ctaTapped))
        buttonRow.addArrangedSubview(ctaButton)

        let notNowButton = makeSecondaryButton(title: "Not now", action: #selector(notNowTapped))
        buttonRow.addArrangedSubview(notNowButton)

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func makePrimaryButton(title: String, action: Selector) -> HoverButton {
        let button = HoverButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.normalBg = theme.accentColor.cgColor
        button.hoverBg = theme.accentColor.withAlphaComponent(0.82).cgColor
        button.layer?.backgroundColor = button.normalBg
        button.layer?.cornerRadius = 12
        button.horizontalContentPadding = 16
        button.verticalContentPadding = 6
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        button.contentTintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func makeSecondaryButton(title: String, action: Selector) -> HoverButton {
        let button = HoverButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.normalBg = theme.bubbleBg.cgColor
        button.hoverBg = theme.accentColor.withAlphaComponent(0.08).cgColor
        button.layer?.backgroundColor = button.normalBg
        button.layer?.cornerRadius = 12
        button.layer?.borderWidth = 1
        button.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.42).cgColor
        button.horizontalContentPadding = 14
        button.verticalContentPadding = 6
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: theme.textPrimary
        ])
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    @objc private func ctaTapped() { onCTATapped?() }
    @objc private func notNowTapped() { onNotNowTapped?() }
}

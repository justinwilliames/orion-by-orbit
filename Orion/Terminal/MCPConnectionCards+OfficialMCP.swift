import AppKit

// MARK: - Official MCP connect card

class OfficialMCPConnectCardView: NSView {
    var onOpenWebsite: (() -> Void)?
    var onSave: (() -> Void)?
    var onBack: (() -> Void)?
    var onDismiss: (() -> Void)?          // X button — clears mcpReconnectNeeded
    var onUseStarterPack: (() -> Void)?   // fallback to starter pack

    private let theme: PopoverTheme
    private let compact: Bool
    private let showsBackButton: Bool
    private let tokenField = NSSecureTextField()
    private let detectionLabel = NSTextField(labelWithString: "")
    private let saveButton = HoverButton(title: "", target: nil, action: nil)

    init(theme: PopoverTheme, compact: Bool = false, showsBackButton: Bool = false) {
        self.theme = theme
        self.compact = compact
        self.showsBackButton = showsBackButton
        super.init(frame: .zero)
        setupViews()
        refreshSaveState()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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
        stack.spacing = compact ? 5 : 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let horizontalInset: CGFloat = 14
        let verticalInset: CGFloat = compact ? 8 : 14
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalInset)
        ])

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleRow)
        titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let title = NSTextField(wrappingLabelWithString: compact ? "Hidden in Orion" : "Hidden in Orion")
        title.font = NSFont.systemFont(ofSize: compact ? 13 : 14, weight: .semibold)
        title.textColor = theme.textPrimary
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(title)

        let compactBadge = makeInfoBadge(title: compact ? "Everything stays local" : "Everything stays local on this Mac.")
        compactBadge.setContentHuggingPriority(.required, for: .horizontal)
        compactBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(compactBadge)

        let titleSpacer = NSView()
        titleSpacer.translatesAutoresizingMaskIntoConstraints = false
        titleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(titleSpacer)

        let xButton = NSButton(title: "", target: self, action: #selector(dismissTapped))
        xButton.bezelStyle = .regularSquare
        xButton.isBordered = false
        xButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        xButton.contentTintColor = theme.textDim
        xButton.imageScaling = .scaleProportionallyDown
        xButton.translatesAutoresizingMaskIntoConstraints = false
        xButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        xButton.heightAnchor.constraint(equalToConstant: 20).isActive = true
        titleRow.addArrangedSubview(xButton)

        if compact {
            addCompactLayout(to: stack)
        } else {
            addFullLayout(to: stack)
        }

        detectionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detectionLabel.textColor = theme.textDim
        detectionLabel.maximumNumberOfLines = 1
        detectionLabel.stringValue = ""
        if compact {
            detectionLabel.isHidden = true
        } else {
            stack.addArrangedSubview(detectionLabel)
            detectionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonRow)

        configurePrimaryButton(saveButton, title: compact ? "Connect" : "Save and connect", action: #selector(saveTapped))
        buttonRow.addArrangedSubview(saveButton)

        if showsBackButton {
            let backButton = makeSecondaryButton(title: "Back", action: #selector(backTapped))
            buttonRow.addArrangedSubview(backButton)
        }

        let starterPackButton = makeSecondaryButton(title: "Use Starter Pack instead", action: #selector(useStarterPackTapped))
        buttonRow.addArrangedSubview(starterPackButton)

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func addCompactLayout(to stack: NSStackView) {
        let body = NSTextField(wrappingLabelWithString: "Archive auth-key flow disabled in Orion.")
        body.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        body.textColor = theme.textDim
        body.maximumNumberOfLines = 1
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let accessRow = NSStackView()
        accessRow.orientation = .horizontal
        accessRow.alignment = .centerY
        accessRow.spacing = 12
        accessRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(accessRow)
        accessRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let tokenRow = makeTokenFieldRow()
        accessRow.addArrangedSubview(tokenRow)
        tokenRow.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let openButton = makeSecondaryButton(title: "Get auth key", action: #selector(openWebsiteTapped))
        openButton.setContentHuggingPriority(.required, for: .horizontal)
        openButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        accessRow.addArrangedSubview(openButton)
    }

    private func addFullLayout(to stack: NSStackView) {
        let body = NSTextField(wrappingLabelWithString: "Archive auth-key flow disabled in Orion.")
        body.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        body.textColor = theme.textDim
        body.maximumNumberOfLines = 2
        stack.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let openButton = makeSecondaryButton(title: "Get auth key", action: #selector(openWebsiteTapped))
        stack.addArrangedSubview(openButton)

        let inputLabel = NSTextField(labelWithString: "Auth key")
        inputLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        inputLabel.textColor = theme.textDim
        stack.addArrangedSubview(inputLabel)
        inputLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let tokenRow = makeTokenFieldRow()
        stack.addArrangedSubview(tokenRow)
        tokenRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeTokenFieldRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.backgroundColor = theme.inputBg.cgColor
        row.layer?.cornerRadius = 12
        row.layer?.borderWidth = 1
        row.layer?.borderColor = theme.separatorColor.withAlphaComponent(0.4).cgColor

        tokenField.translatesAutoresizingMaskIntoConstraints = false
        tokenField.placeholderString = "Paste auth key"
        tokenField.focusRingType = .none
        tokenField.isBordered = false
        tokenField.drawsBackground = false
        tokenField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        tokenField.target = self
        tokenField.action = #selector(tokenFieldChanged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tokenFieldDidChangeNotification(_:)),
            name: NSControl.textDidChangeNotification,
            object: tokenField
        )
        row.addSubview(tokenField)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: compact ? 34 : 38),
            tokenField.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            tokenField.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            tokenField.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return row
    }

    private func makeInfoBadge(title: String) -> NSView {
        let badge = NSView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.backgroundColor = theme.accentColor.withAlphaComponent(0.08).cgColor
        badge.layer?.cornerRadius = 12

        let lockIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: compact ? 8 : 9, weight: .semibold)
            lockIcon.image = img.withSymbolConfiguration(config)
        }
        lockIcon.contentTintColor = theme.accentColor
        lockIcon.imageScaling = .scaleProportionallyDown
        lockIcon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: compact ? 10 : 11, weight: .semibold)
        label.textColor = theme.accentColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let hStack = NSStackView()
        hStack.orientation = .horizontal
        hStack.alignment = .centerY
        hStack.spacing = compact ? 4 : 5
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.addArrangedSubview(lockIcon)
        hStack.addArrangedSubview(label)
        badge.addSubview(hStack)

        NSLayoutConstraint.activate([
            lockIcon.widthAnchor.constraint(equalToConstant: compact ? 9 : 10),
            lockIcon.heightAnchor.constraint(equalToConstant: compact ? 10 : 12),
            hStack.topAnchor.constraint(equalTo: badge.topAnchor, constant: compact ? 4 : 5),
            hStack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: compact ? 8 : 9),
            hStack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -(compact ? 8 : 9)),
            hStack.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -(compact ? 4 : 5))
        ])

        return badge
    }

    private func configurePrimaryButton(_ button: HoverButton, title: String, action: Selector) {
        button.target = self
        button.action = action
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

    private func refreshSaveState() {
        let hasToken = !tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        saveButton.isEnabled = hasToken
        saveButton.alphaValue = hasToken ? 1 : 0.5
    }

    @objc private func tokenFieldChanged() { refreshSaveState() }

    @objc private func tokenFieldDidChangeNotification(_ notification: Notification) { refreshSaveState() }

    @objc private func openWebsiteTapped() { onOpenWebsite?() }

    @objc private func backTapped() { onBack?() }

    @objc private func dismissTapped() { onDismiss?() }

    @objc private func useStarterPackTapped() { onUseStarterPack?() }

    @objc private func saveTapped() {
        let trimmed = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            detectionLabel.textColor = theme.errorColor
            detectionLabel.isHidden = false
            detectionLabel.stringValue = "Paste the auth key first."
            return
        }
        SessionDebugLogger.log("token-entry", "banner: user tapped Save and connect. tokenLength=\(trimmed.count) tokenPrefix=\(String(trimmed.prefix(8)))...")
        do {
            let result = try OfficialMCPInstaller.install(token: trimmed)
            SessionDebugLogger.log("token-entry", "banner: install succeeded. storedTokenOnly=\(result.storedTokenOnly) updated=\(result.updatedTargets.map(\.label).joined(separator: ",")) preserved=\(result.preservedTargets.map(\.label).joined(separator: ","))")
            detectionLabel.textColor = theme.accentColor
            detectionLabel.isHidden = false
            if result.storedTokenOnly {
                detectionLabel.stringValue = "Saved locally. Orion will use it automatically."
            } else {
                detectionLabel.stringValue = "Connected. The key is saved on this Mac and CLI access was configured."
            }
            AppSettings.mcpReconnectNeeded = false
            onSave?()
        } catch {
            SessionDebugLogger.log("token-entry", "banner: install failed. error=\(error.localizedDescription)")
            detectionLabel.textColor = theme.errorColor
            detectionLabel.isHidden = false
            detectionLabel.stringValue = error.localizedDescription
        }
    }
}

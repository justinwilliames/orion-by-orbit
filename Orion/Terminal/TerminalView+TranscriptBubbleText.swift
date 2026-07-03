import AppKit

extension ChatBubbleView {
    func setText(_ newText: NSAttributedString) {
        configureTextContainer()
        textView.textStorage?.setAttributedString(newText)
        updateTextAlignment()
        recalculateSize()
    }

    func appendText(_ newText: NSAttributedString) {
        configureTextContainer()
        textView.textStorage?.append(newText)
        updateTextAlignment()
        recalculateSize()
    }

    @objc func copyTapped() {
        // Slack desktop's WYSIWYG composer ignores plain `*X*` mrkdwn
        // on paste — `*X*` shows up as literal asterisks unless the
        // user has explicitly enabled "Format messages with markup"
        // in Slack preferences (off by default). The fix: write THREE
        // representations to the pasteboard. Slack reads RTF/HTML and
        // applies the formatting; plain text is the fallback for any
        // other consumer.
        //
        //   - .string → Slack-mrkdwn-flavoured plain text. Renders as
        //     bold for users who do have mrkdwn enabled. Otherwise
        //     reads cleanly as ordinary text.
        //   - .rtf    → Rich text built from the markdown source.
        //     Slack desktop, Apple Mail, Notes, and most macOS apps
        //     pick this up and apply bold / italics / lists / links.
        //   - .html   → Same idea, for receivers that prefer HTML
        //     (Slack web/Electron sometimes does).
        let plainText: String
        var rtfData: Data?
        var htmlData: Data?

        if let source = markdownSource, !source.isEmpty {
            plainText = MarkdownToSlack.convert(source)

            // HTML is the format we want every rich-text consumer to
            // pick up. Built from the markdown source via our own
            // emitter (MarkdownToHTML) so paragraph / heading / list
            // block boundaries are explicit and honoured on paste.
            let html = MarkdownToHTML.convert(source)
            let wrapped = "<html><body>\(html)</body></html>"
            let htmlBytes = wrapped.data(using: .utf8)
            htmlData = htmlBytes

            // RTF used to be built from Foundation's
            // AttributedString(markdown:) parser, which collapsed
            // every paragraph boundary into a flat run — Sir saw
            // pasted Slack messages with no spacing between
            // paragraphs even after we shipped the HTML emitter.
            // Slack desktop preferred the RTF on the pasteboard
            // and rendered the collapsed version; the HTML we
            // worked hard on was never picked up.
            //
            // Fix: derive RTF from the HTML we just built, via
            // NSAttributedString(html:). The intermediate attributed
            // string has proper paragraph boundaries (because the
            // HTML did), so the RTF serialisation preserves them.
            // Now both pasteboard formats agree on structure.
            if let htmlBytes,
               let attrFromHTML = try? NSAttributedString(
                   data: htmlBytes,
                   options: [
                       .documentType: NSAttributedString.DocumentType.html,
                       .characterEncoding: String.Encoding.utf8.rawValue
                   ],
                   documentAttributes: nil
               ) {
                let range = NSRange(location: 0, length: attrFromHTML.length)
                rtfData = try? attrFromHTML.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
            }
        } else {
            plainText = textView.string
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        if rtfData != nil { types.append(.rtf) }
        if htmlData != nil { types.append(.html) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(plainText, forType: .string)
        if let rtfData {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        if let htmlData {
            pasteboard.setData(htmlData, forType: .html)
        }
        onCopy?()
    }

    /// Build a neutral-styled `NSAttributedString` from raw markdown
    /// using Foundation's built-in markdown parser (macOS 12+). Used
    /// by the copy action to populate RTF/HTML pasteboard types so
    /// pasting into Slack/Mail/Notes preserves bold / links / lists.
    /// Returns nil when the parser fails — caller falls back to plain
    /// text only.
    static func makeAttributedString(fromMarkdown source: String) -> NSAttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.allowsExtendedAttributes = false
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard let attributed = try? AttributedString(markdown: source, options: options) else {
            return nil
        }
        return NSAttributedString(attributed)
    }

    /// Update the bubble's markdown source as new content streams in.
    /// Called from the streaming path so the copy button always
    /// reflects the latest accumulated markdown.
    func setMarkdownSource(_ source: String) {
        markdownSource = source
    }

    @objc func followUpTapped() {
        WalkerCharacter.playSelectionSound()
        onFollowUp?()
    }

    func configureTextContainer() {
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)
    }

    func updateTextAlignment() {
        guard let storage = textView.textStorage else { return }

        let alignment: NSTextAlignment = .left

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.alignment = alignment
            if style.lineSpacing == 0 {
                style.lineSpacing = 4
            }
            if style.paragraphSpacing == 0 {
                style.paragraphSpacing = 7
            }
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
        textView.alignment = alignment
    }

    func recalculateSize() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        textContainer.containerSize = NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)

        let targetContentWidth = rect.width
        let paddingWidth: CGFloat = 28
        // `maxBubbleWidth` is set by the parent `TerminalView` after each
        // layout pass — see TerminalView.layout(). Soft-capped at 720
        // there so very wide popovers don't produce hard-to-read line
        // lengths. Default stays at 380 for the initial render before
        // the parent has had a chance to compute the column width.
        let maxWidth: CGFloat = max(280, maxBubbleWidth)
        let desiredWidth = targetContentWidth + paddingWidth

        if let textWidthConstraint {
            textView.removeConstraint(textWidthConstraint)
            self.textWidthConstraint = nil
        }
        if let textHeightConstraint {
            textView.removeConstraint(textHeightConstraint)
            self.textHeightConstraint = nil
        }

        if desiredWidth >= maxWidth {
            textContainer.containerSize = NSSize(width: maxWidth - paddingWidth, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let newRect = layoutManager.usedRect(for: textContainer)
            textWidthConstraint = textView.widthAnchor.constraint(equalToConstant: maxWidth)
            textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: newRect.height + 24)
        } else {
            let finalWidth = max(desiredWidth, 60)
            textWidthConstraint = textView.widthAnchor.constraint(equalToConstant: finalWidth)
            textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: rect.height + 24)
        }

        textWidthConstraint?.isActive = true
        textHeightConstraint?.isActive = true
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        var view: NSView? = self.superview
        while let v = view {
            if let terminal = v as? TerminalView {
                guard let url = link as? URL,
                      url.scheme == "lilagents-expert",
                      let host = url.host,
                      let expert = terminal.expertSuggestionTargets[host] else {
                    return false
                }
                WalkerCharacter.playSelectionSound()
                terminal.onSelectExpert?(expert)
                return true
            }
            view = v.superview
        }
        return false
    }
}

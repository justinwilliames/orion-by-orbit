import Foundation

/// Convert markdown to HTML so a Orion reply can be copied to
/// Slack (and Apple Mail / Notes / Notion / Linear) and pasted with
/// formatting intact.
///
/// **Why this exists alongside MarkdownToSlack and the AttributedString
/// path we tried earlier:** Slack desktop's WYSIWYG composer needs
/// rich-text input on the pasteboard to render formatting at all
/// (plain Slack mrkdwn `*X*` shows as literal asterisks unless the
/// user has the legacy "Format messages with markup" preference on).
/// Apple's `AttributedString(markdown:)` produces a flat
/// AttributedString where headings/paragraphs/lists are marked as
/// presentation-intent attributes but no actual line breaks exist
/// in the string — so when serialized to RTF, all the text smashes
/// together. Sir's screenshot showed "worse.That's" / "mechanismThe"
/// / "pair.SourcesEmojis" — multiple paragraphs collapsed into one.
///
/// This module emits HTML directly so paragraph and block boundaries
/// are unambiguous. Slack reads `<p>`, `<strong>`, `<a>`, `<ul>`,
/// `<blockquote>` etc. natively on paste and renders them correctly.
///
/// Conservative line-based parser, same shape as MarkdownToSlack:
/// no full CommonMark conformance, just the constructs Orion
/// actually emits in answers.
enum MarkdownToHTML {

    /// Convert the supplied markdown to a self-contained HTML string
    /// suitable for the `.html` pasteboard type. Returns plain `<p>`-
    /// only output for empty/whitespace input.
    static func convert(_ markdown: String) -> String {
        let normalised = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalised.components(separatedBy: "\n")

        var output: [String] = []
        var paragraphLines: [String] = []
        var listItems: [String] = []
        var listKind: ListKind? = nil
        var fenceLines: [String] = []
        var inFenced = false
        var tableLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            // Join paragraph lines with a single space — markdown
            // wraps soft line breaks but the rendered paragraph is
            // one logical block.
            let combined = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            output.append("<p>\(transformInline(combined))</p>")
            paragraphLines.removeAll()
        }

        func flushList() {
            guard let kind = listKind, !listItems.isEmpty else {
                listItems.removeAll()
                listKind = nil
                return
            }
            let tag = (kind == .ordered) ? "ol" : "ul"
            output.append("<\(tag)>\(listItems.joined())</\(tag)>")
            listItems.removeAll()
            listKind = nil
        }

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            // Tables paste catastrophically when run through Slack's
            // WYSIWYG composer — `<table>` rendering is unpredictable
            // and HTML→AttributedString conversion in some clients
            // collapses every cell to plain text on one line. Most
            // reliable cross-client rendering: emit the markdown
            // table verbatim inside a <pre><code> block. Monospace
            // rendering preserves the column alignment, and Slack /
            // Apple Mail / Notes / Notion all honour it.
            output.append("<pre><code>\(escape(tableLines.joined(separator: "\n")))</code></pre>")
            tableLines.removeAll()
        }

        for line in lines {
            // Fenced code block boundary.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inFenced {
                    output.append("<pre><code>\(escape(fenceLines.joined(separator: "\n")))</code></pre>")
                    fenceLines.removeAll()
                } else {
                    flushParagraph()
                    flushList()
                    flushTable()
                }
                inFenced.toggle()
                continue
            }
            if inFenced {
                fenceLines.append(line)
                continue
            }

            // Markdown table row — `| col | col |` shape. We collect
            // consecutive `|` lines and emit them as a code block so
            // the column alignment survives the Slack paste.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                flushParagraph()
                flushList()
                tableLines.append(line)
                continue
            }
            // Any non-table line ends a pending table.
            if !tableLines.isEmpty {
                flushTable()
            }

            // Heading. Emit as a bolded paragraph rather than an
            // <h1>-<h6> tag — Slack's paste handler renders `<h>`
            // with no blank line above the next paragraph.
            //
            // Iteration history:
            //   - v0.1.49: <p><strong>X</strong></p> only. Slack
            //     collapsed the gap to the next paragraph.
            //   - v0.1.53: added an empty <p></p> sentinel after.
            //     Worked sometimes but NSAttributedString(html:) and
            //     Slack's HTML parser both normalise empty paragraphs
            //     out, so the sentinel didn't survive HTML→RTF or
            //     the WYSIWYG paste handler reliably.
            //   - now: sentinel is `<p>&nbsp;</p>` — non-breaking
            //     space content makes the paragraph "non-empty" so
            //     it survives every round-trip and renders as a
            //     blank line in every consumer.
            if let (level, content) = headingMatch(line) {
                flushParagraph()
                flushList()
                _ = level
                output.append("<p><strong>\(transformInline(content))</strong></p>")
                output.append("<p>&nbsp;</p>")
                continue
            }

            // Blockquote.
            if let quoted = blockquoteContent(line) {
                flushParagraph()
                flushList()
                output.append("<blockquote>\(transformInline(quoted))</blockquote>")
                continue
            }

            // Unordered list item.
            if let item = unorderedListItem(line) {
                flushParagraph()
                if listKind != .unordered { flushList(); listKind = .unordered }
                listItems.append("<li>\(formatListItemContent(item))</li>")
                continue
            }

            // Ordered list item.
            if let item = orderedListItem(line) {
                flushParagraph()
                if listKind != .ordered { flushList(); listKind = .ordered }
                listItems.append("<li>\(formatListItemContent(item))</li>")
                continue
            }

            // Horizontal rule.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                flushList()
                output.append("<hr>")
                continue
            }

            // Empty line — closes any pending block.
            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            // Default — accumulate into the current paragraph.
            paragraphLines.append(line)
        }

        // Drain anything still pending at end of input.
        flushParagraph()
        flushList()
        flushTable()
        if inFenced && !fenceLines.isEmpty {
            output.append("<pre><code>\(escape(fenceLines.joined(separator: "\n")))</code></pre>")
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Inline transforms

    /// Apply inline transforms in an order that prevents one transform
    /// from corrupting another's boundaries:
    ///   1. Pull out inline code spans behind opaque placeholders so
    ///      bold/italic/link passes can't touch their contents.
    ///   2. Pull out markdown links the same way (their URL contents
    ///      shouldn't be HTML-escaped or mangled by bold/italic).
    ///   3. HTML-escape remaining user text.
    ///   4. Bold (`**X**` → `<strong>X</strong>`).
    ///   5. Italic (`*X*` / `_X_` → `<em>X</em>`).
    ///   6. Bare URLs → `<a>`.
    ///   7. Restore links + code spans.
    static func transformInline(_ input: String) -> String {
        var (text, codeSpans) = extractInlineCode(input)
        var links: [(label: String, url: String)] = []
        text = extractMarkdownLinks(text, into: &links)
        text = escape(text)
        text = applyBold(text)
        text = applyItalic(text)
        text = autolinkBareURLs(text)
        text = restoreMarkdownLinks(text, links: links)
        text = restoreInlineCode(text, spans: codeSpans)
        return text
    }

    private static func extractInlineCode(_ text: String) -> (String, [String]) {
        var result = ""
        var spans: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "`" {
                let after = text.index(after: index)
                if after < text.endIndex, let close = text[after...].firstIndex(of: "`") {
                    let inside = String(text[after..<close])
                    spans.append(inside)
                    result.append("\u{E000}\(spans.count - 1)\u{E001}")
                    index = text.index(after: close)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return (result, spans)
    }

    private static func restoreInlineCode(_ text: String, spans: [String]) -> String {
        guard !spans.isEmpty else { return text }
        var result = text
        for (i, span) in spans.enumerated() {
            // Escape the code contents now (during restore), since
            // earlier escape() pass skipped them.
            result = result.replacingOccurrences(
                of: "\u{E000}\(i)\u{E001}",
                with: "<code>\(escape(span))</code>"
            )
        }
        return result
    }

    private static func extractMarkdownLinks(_ text: String, into links: inout [(label: String, url: String)]) -> String {
        let pattern = #"\[([^\]]+)\]\(([^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed()
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let label = result.substring(with: match.range(at: 1))
            let url = result.substring(with: match.range(at: 2))
            links.append((label: label, url: url))
            let placeholder = "\u{E002}\(links.count - 1)\u{E003}"
            result = result.replacingCharacters(in: match.range, with: placeholder) as NSString
        }
        return result as String
    }

    private static func restoreMarkdownLinks(_ text: String, links: [(label: String, url: String)]) -> String {
        guard !links.isEmpty else { return text }
        var result = text
        for (i, link) in links.enumerated() {
            let anchor = "<a href=\"\(escape(link.url))\">\(escape(link.label))</a>"
            result = result.replacingOccurrences(of: "\u{E002}\(i)\u{E003}", with: anchor)
        }
        return result
    }

    private static func applyBold(_ text: String) -> String {
        let pattern = #"\*\*([^*\n][^*\n]*?)\*\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "<strong>$1</strong>")
    }

    private static func applyItalic(_ text: String) -> String {
        // Two patterns. Underscore italic is unambiguous; single-
        // asterisk italic must be careful not to fire on the closing
        // marker of a `**bold**` run. By the time this function runs,
        // bold has already been transformed to `<strong>X</strong>`
        // so any remaining `*` is genuinely italic. We still guard
        // with negative lookarounds to skip stray asterisks adjacent
        // to other asterisks (defence in depth).
        var result = text

        // Underscore form first.
        if let underscoreRegex = try? NSRegularExpression(pattern: #"\b_([^_\n]+)_\b"#) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = underscoreRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "<em>$1</em>")
        }

        // Single-asterisk form. `(?<!\*)\*([^*\n]+)\*(?!\*)` — match
        // a single `*`, capture the content, match a single `*`,
        // none of which are adjacent to another `*`. The content
        // class excludes `*` and newlines so we never gulp across
        // unintended boundaries.
        if let asteriskRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = asteriskRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "<em>$1</em>")
        }

        return result
    }

    private static func autolinkBareURLs(_ text: String) -> String {
        // Skip URLs already inside an `<a>` (we restored markdown
        // links earlier, and those have angle brackets surrounding
        // their href). The negative lookbehind on `"` keeps us off
        // them.
        let pattern = #"(?<![\"=>])\bhttps?://[^\s<>)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "<a href=\"$0\">$0</a>")
    }

    // MARK: - Block detection

    private static func headingMatch(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes: [(String, Int)] = [
            ("###### ", 6), ("##### ", 5), ("#### ", 4),
            ("### ", 3),    ("## ", 2),    ("# ", 1)
        ]
        for (prefix, level) in prefixes {
            if trimmed.hasPrefix(prefix) {
                return (level, String(trimmed.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static func blockquoteContent(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("> ") {
            return String(trimmed.dropFirst(2))
        }
        if trimmed == ">" { return "" }
        return nil
    }

    private static func unorderedListItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "• "] {
            if trimmed.hasPrefix(marker) {
                return String(trimmed.dropFirst(marker.count))
            }
        }
        return nil
    }

    private static func orderedListItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = try? NSRegularExpression(pattern: #"^\d+\.\s+(.*)$"#).firstMatch(
            in: trimmed,
            range: NSRange(location: 0, length: (trimmed as NSString).length)
        ) else { return nil }
        guard match.numberOfRanges >= 2 else { return nil }
        return (trimmed as NSString).substring(with: match.range(at: 1))
    }

    private enum ListKind {
        case unordered
        case ordered
    }

    /// Render a list item's content, with one ergonomic adjustment:
    /// when the item starts with a bold prefix followed by more text
    /// (e.g. `**Authentication** SPF, DKIM, and DMARC...`), break
    /// after the bold so the rendered list reads as `title / body`
    /// rather than running together. Sir's pattern is to use the
    /// inline form for short numbered lists; the visual break makes
    /// pasted Slack output mirror the original message's structure.
    static func formatListItemContent(_ markdown: String) -> String {
        let inline = transformInline(markdown)
        // Look for a strong-tag at the very start, followed by
        // whitespace, followed by at least one word of body text.
        // Anchored with `^` so we only match prefix bolds, never
        // mid-line emphasis.
        let pattern = #"^(<strong>[^<]+</strong>)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return inline
        }
        let range = NSRange(location: 0, length: (inline as NSString).length)
        guard let match = regex.firstMatch(in: inline, range: range), match.numberOfRanges >= 3 else {
            return inline
        }
        let nsString = inline as NSString
        let bold = nsString.substring(with: match.range(at: 1))
        let rest = nsString.substring(with: match.range(at: 2))
        return "\(bold)<br>\(rest)"
    }

    // MARK: - HTML escaping

    /// Escape the four characters that could break out of an HTML
    /// text node or attribute. Kept narrow — we don't escape `'`
    /// because we use only double-quoted attributes; we don't
    /// escape `"` in text contexts because attribute values are the
    /// only place it matters and we always escape both label and
    /// href before constructing an `<a>`.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

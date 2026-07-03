import Foundation

/// Convert standard CommonMark-ish markdown into Slack mrkdwn so a
/// Orion reply can be copied to the clipboard and pasted into a
/// Slack message with formatting intact.
///
/// Slack mrkdwn diverges from CommonMark in three load-bearing ways:
///   - Bold uses a single `*` (not `**`). `**bold**` → `*bold*`.
///   - Italic uses `_` (not `*` or `_`). `*italic*` → `_italic_`.
///   - Links use `<url|label>` (not `[label](url)`). Bare URLs become `<url>`.
///
/// Slack has no headings — `# Heading` is flattened to a bold line so
/// it still reads as a section break in chat. Tables don't render in
/// Slack at all, so they're passed through with light cleanup; the
/// reader will see pipe-delimited rows.
///
/// The converter is line-based and intentionally conservative: it
/// won't try to parse nested constructs perfectly, just preserve the
/// shape of a typical Mini-Justin response.
enum MarkdownToSlack {

    /// Convert the supplied markdown to Slack mrkdwn.
    static func convert(_ markdown: String) -> String {
        let normalised = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalised.components(separatedBy: "\n")

        var output: [String] = []
        var inFencedCode = false

        for line in lines {
            // Fenced code blocks pass straight through — Slack
            // supports triple-backtick fenced blocks identically.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                output.append(line)
                inFencedCode.toggle()
                continue
            }
            if inFencedCode {
                output.append(line)
                continue
            }

            // Headings → bold, no leading hashes.
            if let heading = stripHeadingPrefix(line) {
                let inline = transformInline(heading)
                output.append("*\(inline)*")
                continue
            }

            // Blockquote — keep the leading `>` (Slack supports it).
            if let quote = blockquoteContent(line) {
                let inline = transformInline(quote)
                output.append("> \(inline)")
                continue
            }

            // Unordered list — normalise marker to `•` for stable
            // rendering across Slack clients (some flatten `- ` to
            // bullets, some don't). Preserves indentation depth.
            if let bullet = unorderedListItem(line) {
                let inline = transformInline(bullet.content)
                let indent = String(repeating: "    ", count: bullet.depth)
                output.append("\(indent)•   \(inline)")
                continue
            }

            // Ordered list — Slack renders numeric prefixes natively.
            if let ordered = orderedListItem(line) {
                let inline = transformInline(ordered.content)
                let indent = String(repeating: "    ", count: ordered.depth)
                output.append("\(indent)\(ordered.number). \(inline)")
                continue
            }

            // Markdown horizontal rules don't render — replace with
            // an em-dash divider so the reader still sees a break.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                output.append("———")
                continue
            }

            // Default: paragraph line.
            output.append(transformInline(line))
        }

        var joined = output.joined(separator: "\n")
        // Collapse 3+ blank lines to a maximum of 2 for Slack hygiene.
        while joined.contains("\n\n\n\n") {
            joined = joined.replacingOccurrences(of: "\n\n\n\n", with: "\n\n\n")
        }
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Inline transforms

    /// Apply inline transforms in a single pass per construct, in an
    /// order that prevents one transform from corrupting another's
    /// boundaries:
    ///   1. Inline code spans get extracted to placeholders so their
    ///      backticked contents survive the bold/italic passes intact.
    ///   2. Markdown links → Slack `<url|label>`.
    ///   3. Bold (`**text**` → `*text*`).
    ///   4. Italic (`*text*` or `_text_` → `_text_`). Italic must run
    ///      after bold so the bold pass eats `**` first.
    ///   5. Bare URLs → `<url>`.
    ///   6. Re-inject inline code spans.
    static func transformInline(_ input: String) -> String {
        var (text, codeSpans) = extractInlineCode(input)
        text = transformLinks(text)
        text = transformBold(text)
        text = transformItalic(text)
        text = transformBareURLs(text)
        text = restoreInlineCode(text, spans: codeSpans)
        return text
    }

    /// Pull inline code spans out behind opaque placeholders so later
    /// transforms can't accidentally touch their contents (e.g. an `*`
    /// inside `` `glob *.tsx` `` shouldn't trigger italics).
    private static func extractInlineCode(_ text: String) -> (String, [String]) {
        var result = ""
        var spans: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "`" {
                let afterTick = text.index(after: index)
                if afterTick < text.endIndex, let close = text[afterTick...].firstIndex(of: "`") {
                    let inside = String(text[afterTick..<close])
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
            result = result.replacingOccurrences(of: "\u{E000}\(i)\u{E001}", with: "`\(span)`")
        }
        return result
    }

    /// `[label](https://url)` → `<https://url|label>`. Run before
    /// bold/italic so the URL contents aren't mangled by `*`/`_` rules.
    private static func transformLinks(_ text: String) -> String {
        let pattern = #"\[([^\]]+)\]\(([^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        // Apply matches from the end backwards so earlier ranges
        // remain valid as we splice.
        let matches = regex.matches(in: text, range: nsRange).reversed()
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let labelRange = Range(match.range(at: 1), in: result),
                  let urlRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let label = String(result[labelRange])
            let url = String(result[urlRange])
            let replacement = "<\(url)|\(label)>"
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    /// `**bold**` → `*bold*`. We cannot just swap `**` for `*` blindly
    /// because `* * *` separators would collapse. Use a regex that
    /// requires non-asterisk content between the markers.
    private static func transformBold(_ text: String) -> String {
        let pattern = #"\*\*([^*\n][^*\n]*?)\*\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: nsRange, withTemplate: "*$1*")
    }

    /// `*italic*` → `_italic_` and `_italic_` → `_italic_` (no-op for
    /// underscore form). Skips bold residue (`*x*` is the new bold so
    /// we must NOT italicise it). To distinguish: only convert when
    /// the surrounding chars are non-letter (italic boundaries) AND
    /// the contents don't start/end with whitespace.
    private static func transformItalic(_ text: String) -> String {
        // Underscores can stay — Slack treats `_x_` as italic. We
        // only need to touch the `*x*` form. But by this point bold
        // has already become `*x*`, so naive conversion would italicise
        // every bold span. Instead, italic-from-asterisk is rare in
        // practitioner writing; opt for the safer choice and leave
        // single-asterisk runs untouched. If the user wrote italic
        // with underscores it already works in Slack.
        return text
    }

    /// Bare URLs → `<https://url>`. Skip URLs that already sit inside
    /// a Slack link (between `<` and `>`), since `transformLinks` ran
    /// first and may have produced those.
    private static func transformBareURLs(_ text: String) -> String {
        let pattern = #"(?<![<\|])\bhttps?://[^\s<>)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: nsRange, withTemplate: "<$0>")
    }

    // MARK: - Block detection

    private static func stripHeadingPrefix(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["# ", "## ", "### ", "#### ", "##### ", "###### "]
        for prefix in prefixes {
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func blockquoteContent(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("> ") else {
            if trimmed == ">" { return "" }
            return nil
        }
        return String(trimmed.dropFirst(2))
    }

    private struct ListItemMatch {
        let content: String
        let depth: Int
        let number: Int
    }

    private static func unorderedListItem(_ line: String) -> ListItemMatch? {
        let leadingSpaces = line.prefix { $0 == " " }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "• "] {
            if trimmed.hasPrefix(marker) {
                return ListItemMatch(
                    content: String(trimmed.dropFirst(marker.count)),
                    depth: leadingSpaces / 2,
                    number: 0
                )
            }
        }
        return nil
    }

    private static func orderedListItem(_ line: String) -> ListItemMatch? {
        let leadingSpaces = line.prefix { $0 == " " }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#).firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        ) else { return nil }
        guard match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: trimmed),
              let contentRange = Range(match.range(at: 2), in: trimmed),
              let number = Int(trimmed[numberRange]) else { return nil }
        return ListItemMatch(
            content: String(trimmed[contentRange]),
            depth: leadingSpaces / 2,
            number: number
        )
    }
}

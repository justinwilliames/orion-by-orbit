import Foundation

/// Safety net for citation rendering.
///
/// The system prompt instructs Orion to emit Orbit guide
/// citations as proper markdown links — `[Title](https://yourorbit.team/guides/<slug>)`.
/// When he does, the renderer makes them clickable. This module catches
/// the slip-cases: he names a slug as a bare token (`see apple-mpp-four-years`,
/// or a `Sources` block listed as raw slugs without the link wrapper).
///
/// On every assistant message, we sweep the markdown for known slugs
/// that aren't already wrapped in a markdown link or sitting inside
/// inline code / a fenced code block, and rewrite them into the
/// canonical `[Title](URL)` form. Slugs not present in the live Orbit
/// corpus are left alone — we never invent a guide.
enum CitationLinkifier {

    /// Linkify any bare Orbit guide slugs in the supplied markdown.
    /// Returns the input unchanged when the corpus is empty or no
    /// bare slugs are present.
    static func linkify(_ markdown: String) -> String {
        let entries = OrbitGuidesCorpus.entries
        guard !entries.isEmpty else { return markdown }

        // Sort longest slugs first so a substring slug never wins
        // against a longer real slug. Without this, `apple-mpp` would
        // match the prefix of `apple-mpp-four-years` and rewrite the
        // wrong span.
        let sortedEntries = entries.sorted { $0.slug.count > $1.slug.count }

        // Walk line-by-line so we can skip fenced code block contents
        // outright. Within each non-code line we use a single regex
        // pass per slug with explicit lookarounds that exclude already-
        // linked slugs and inline-code spans.
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output: [String] = []
        var inFencedCode = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                output.append(line)
                inFencedCode.toggle()
                continue
            }
            if inFencedCode {
                output.append(line)
                continue
            }

            var processed = line
            for entry in sortedEntries {
                processed = linkifyOne(
                    line: processed,
                    slug: entry.slug,
                    title: entry.title,
                    url: entry.canonicalUrl
                )
            }
            output.append(processed)
        }

        return output.joined(separator: "\n")
    }

    /// Replace bare `slug` occurrences in `line` with `[title](url)`.
    /// Negative lookarounds keep us off slugs that are already part of
    /// a markdown link, inside backticks, or part of a longer slug.
    ///
    /// Lookbehind `(?<![\w\-\[\(\`/])` excludes:
    ///   `\w-` → middle of a longer slug or word
    ///   `[`   → label opener of an existing markdown link `[slug]...`
    ///   `(`   → URL opener of an existing markdown link `](.../slug)`
    ///   `` ` ``→ inside an inline code span
    ///   `/`   → already a path component in a URL
    ///
    /// Lookahead `(?![\w\-\]\)\`/])` excludes the same trailing cases.
    private static func linkifyOne(line: String, slug: String, title: String, url: String) -> String {
        let escapedSlug = NSRegularExpression.escapedPattern(for: slug)
        let pattern = #"(?<![\w\-\[\(`/])"# + escapedSlug + #"(?![\w\-\]\)`/])"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else { return line }

        // Apply replacements from the end backwards so earlier ranges
        // remain valid as we splice in the longer link form.
        var result = line as NSString
        let replacement = "[\(title)](\(url))"
        for match in matches.reversed() {
            result = result.replacingCharacters(in: match.range, with: replacement) as NSString
        }
        return result as String
    }
}

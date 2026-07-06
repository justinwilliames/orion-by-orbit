import Foundation

/// Pure-logic helpers for extracting Orion's structured JSON
/// response from raw CLI output. Lives outside `ClaudeSession` so it
/// can be exercised by `swift test` without spinning up an AppKit
/// session — when the parser fails, the whole transcript renders the
/// raw JSON to the user (Sir's 2026-04-30 screenshot bug). Locking
/// the failure modes down with regression tests is the only durable
/// fix.
///
/// The parser is layered:
///   1. `extractCandidate` peels prose / code-fence wrapping off the
///      raw output and returns the smallest balanced `{...}` block
///      that contains one of the expected schema keys.
///   2. `decode` parses that candidate as JSON. Strict parse first;
///      if that fails (LLMs frequently emit raw newlines inside the
///      `markdown` string), retry with `sanitiseJSONStrings` which
///      escapes raw control chars inside string literals.
///   3. `extractMessageMarkdownFallback` is a last-ditch path: when
///      JSON parsing fails entirely, regex out just the `markdown`
///      field's value so the user sees the prose content rather than
///      the raw JSON envelope. Better degraded UX than the silent
///      "all of nothing" failure.
enum StructuredJSONParser {

    // MARK: - Public entry points

    /// Top-level parse. Returns the decoded JSON dictionary if any
    /// strategy succeeds, nil otherwise.
    static func decodeJSONObject(from outputText: String) -> [String: Any]? {
        let normalized = outputText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let direct = decodeCandidate(normalized) {
            return direct
        }

        if let candidate = extractCandidate(from: normalized),
           let decoded = decodeCandidate(candidate) {
            return decoded
        }

        return nil
    }

    /// Strip prose / code-fence wrapping and return the JSON object
    /// candidate string (or nil if no recognisable block found).
    static func extractCandidate(from outputText: String) -> String? {
        let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .replacingOccurrences(of: #"^```json\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^```\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("{"), normalized.hasSuffix("}") {
            return normalized
        }

        let characters = Array(normalized)
        for startIndex in characters.indices where characters[startIndex] == "{" {
            var depth = 0
            var inString = false
            var escaping = false

            for index in startIndex..<characters.count {
                let character = characters[index]

                if inString {
                    if escaping {
                        escaping = false
                    } else if character == "\\" {
                        escaping = true
                    } else if character == "\"" {
                        inString = false
                    }
                    continue
                }

                if character == "\"" {
                    inString = true
                    continue
                }

                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let candidate = String(characters[startIndex...index])
                        if candidate.contains("\"answer_markdown\"") || candidate.contains("\"messages\"") {
                            return candidate
                        }
                        break
                    }
                }
            }
        }

        return nil
    }

    /// Last-ditch extraction: when full JSON parsing fails, regex out
    /// the first `markdown` string value so the user sees prose
    /// instead of raw JSON. Single-pass; quotes inside the markdown
    /// are expected to be backslash-escaped per the system prompt's
    /// OUTPUT FORMAT rules.
    static func extractMessageMarkdownFallback(from outputText: String) -> String? {
        // Look for `"markdown": "..."` — the pattern Orion's output
        // schema specifies. The capture group is non-greedy and
        // permits escaped quotes inside.
        let pattern = #"\"markdown\"\s*:\s*\"((?:[^\"\\]|\\.)*)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(outputText.startIndex..<outputText.endIndex, in: outputText)
        guard let match = regex.firstMatch(in: outputText, options: [], range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: outputText) else {
            return nil
        }
        return unescapeJSONString(String(outputText[captureRange]))
    }

    /// Streaming-safe display text. While a structured response streams
    /// in, the `markdown` value has no closing quote yet, so the
    /// complete-match fallbacks return nil and the raw JSON envelope
    /// leaks to the user. This peels the `markdown` value out even when
    /// it's still open — extracting everything after `"markdown":"` up
    /// to the first unescaped quote (or end of stream), unescaping as it
    /// goes. Non-structured prose (doesn't start with `{`, or has no
    /// `markdown` field) is returned unchanged, so it's a safe no-op on
    /// the final clean displayText too.
    static func streamingDisplayText(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let marker = trimmed.range(of: #"\"markdown\"\s*:\s*\""#, options: .regularExpression) else {
            return raw
        }
        var result = ""
        var escaping = false
        for ch in trimmed[marker.upperBound...] {
            if escaping {
                switch ch {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                default: result.append(ch)
                }
                escaping = false
                continue
            }
            if ch == "\\" { escaping = true; continue }
            if ch == "\"" { break }   // closing quote → end of the markdown value
            result.append(ch)
        }
        return result.isEmpty ? raw : result
    }

    // MARK: - Internal helpers (visible for testing)

    /// Single-candidate parse with strict-then-sanitised retry.
    static func decodeCandidate(_ candidate: String) -> [String: Any]? {
        if let object = parseJSON(candidate) {
            return interpretStructured(object)
        }
        let sanitised = sanitiseJSONStrings(candidate)
        if sanitised != candidate, let object = parseJSON(sanitised) {
            return interpretStructured(object)
        }
        return nil
    }

    /// Walks the candidate tracking quote / backslash state and
    /// escapes raw newlines / carriage returns / tabs inside string
    /// literals. The model is told to emit `\n` etc. itself (per
    /// OUTPUT FORMAT in the system prompt), but in practice LLMs
    /// regularly forget for long markdown bodies. This makes parsing
    /// robust to that drift.
    static func sanitiseJSONStrings(_ input: String) -> String {
        var output = ""
        output.reserveCapacity(input.count)
        var inString = false
        var escaped = false
        for char in input {
            if escaped {
                output.append(char)
                escaped = false
                continue
            }
            if char == "\\" {
                output.append(char)
                escaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                output.append(char)
                continue
            }
            if inString {
                switch char {
                case "\n": output.append("\\n"); continue
                case "\r": output.append("\\r"); continue
                case "\t": output.append("\\t"); continue
                default: break
                }
            }
            output.append(char)
        }
        return output
    }

    // MARK: - Private

    private static func parseJSON(_ candidate: String) -> Any? {
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// A valid Orion structured payload is a JSON object containing
    /// either `answer_markdown` (string) or `messages` (array). If the
    /// outer object is itself a JSON-encoded string (some CLI wrappers
    /// double-encode), recurse once to unwrap.
    private static func interpretStructured(_ object: Any) -> [String: Any]? {
        if let json = object as? [String: Any],
           json["answer_markdown"] is String || json["messages"] is [[String: Any]] {
            return json
        }
        if let wrapped = object as? String {
            let trimmed = wrapped.trimmingCharacters(in: .whitespacesAndNewlines)
            if let nested = decodeCandidate(trimmed) {
                return nested
            }
            if let nestedCandidate = extractCandidate(from: trimmed) {
                return decodeCandidate(nestedCandidate)
            }
        }
        return nil
    }

    /// Unescape the standard JSON string escapes (`\"`, `\\`, `\n`,
    /// `\r`, `\t`) so the fallback markdown reads naturally to the
    /// user even when the surrounding JSON envelope is broken.
    private static func unescapeJSONString(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var iterator = input.makeIterator()
        while let char = iterator.next() {
            if char != "\\" {
                result.append(char)
                continue
            }
            guard let next = iterator.next() else {
                result.append(char)
                break
            }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "/": result.append("/")
            default:
                result.append(char)
                result.append(next)
            }
        }
        return result
    }
}

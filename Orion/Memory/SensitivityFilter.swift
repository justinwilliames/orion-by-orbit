import Foundation

/// Pre-save guard that rejects memory candidates containing the kinds
/// of strings Sir specifically asked Caldwell to avoid memorising:
/// PII, authentication secrets, financial precision, internal IDs.
///
/// This is a safety net, not a substitute for prompt-side guidance.
/// The extraction prompt also tells the model to generalise sensitive
/// specifics — but models drift, so a Swift-side filter catches drift.
///
/// **Philosophy: refuse, don't redact.** A redacted memory often loses
/// the meaning it was trying to capture. Cleaner to drop the memory
/// entirely and let the user explicitly capture a generalised version
/// with `remember that...` if they want.
///
/// Detected patterns (rejected on any match in the body):
///   - Email addresses
///   - Phone numbers (international + US)
///   - API key patterns (sk-, pk-, xoxb-, ghp_, etc.)
///   - JWT-shaped tokens
///   - Credit card patterns (Luhn-shaped 13–19 digit runs)
///   - High-precision currency (e.g. $487,213.00) — generalised forms
///     like "~500K subscribers" still pass
///   - Specific person names paired with organisation context that
///     would identify a customer
enum SensitivityFilter {

    enum Decision: Equatable {
        case allow
        case reject(reason: String)
    }

    static func evaluate(_ entry: MemoryEntry) -> Decision {
        let combined = "\(entry.name) \(entry.description) \(entry.body)"
        return evaluate(text: combined)
    }

    static func evaluate(text: String) -> Decision {
        for check in checks {
            if let match = firstMatch(text, pattern: check.pattern) {
                return .reject(reason: "Detected \(check.label): \(match)")
            }
        }
        return .allow
    }

    private struct Check {
        let label: String
        let pattern: String
    }

    /// Order matters loosely — most specific / least false-positive first.
    private static let checks: [Check] = [
        // API keys — distinctive prefixes, fail fast.
        Check(label: "API key", pattern: #"\b(?:sk|pk|rk)[-_][A-Za-z0-9]{16,}\b"#),
        Check(label: "Slack/GitHub token", pattern: #"\b(?:xox[abprs]-|ghp_|gho_|ghu_|ghr_|github_pat_)[A-Za-z0-9_-]{16,}\b"#),
        Check(label: "AWS key", pattern: #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#),
        Check(label: "JWT", pattern: #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#),

        // Email addresses.
        Check(label: "email address", pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#),

        // Phone numbers — at least 8 digits with separators or a leading +.
        // Skip simple short numbers like "v0.1.36" or "100k" by requiring
        // either a + prefix, parentheses, or 3+ separator-bounded groups.
        Check(label: "phone number", pattern: #"(?:\+\d[\d\s\-().]{6,}\d|\(\d{2,4}\)[\s\-]?\d{3}[\s\-]?\d{3,4}|\b\d{3}[\s\-]\d{3}[\s\-]\d{4}\b)"#),

        // Credit card-shaped digit runs (13–19 digits, optional spaces/dashes).
        // High false-positive risk on years/IDs, so guard with word boundaries.
        Check(label: "card number", pattern: #"\b(?:\d[ -]?){12,18}\d\b"#),

        // High-precision currency: $487,213.00 / £1,234.56 — these are
        // almost always real revenue/LTV figures the model shouldn't keep.
        // Generalised forms ("~$500K", "~500K subscribers") pass.
        Check(label: "precise currency figure", pattern: #"[\$£€¥]\s?\d{1,3}(?:,\d{3}){2,}(?:\.\d{2})?"#),

        // SSN / TFN-shaped runs (US, AU).
        Check(label: "national ID", pattern: #"\b\d{3}-\d{2}-\d{4}\b|\b\d{3}\s\d{3}\s\d{3}\b"#),

        // IBAN-shaped strings.
        Check(label: "IBAN", pattern: #"\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b"#),
    ]

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        let preview = String(text[matchRange])
        return preview.count > 24 ? String(preview.prefix(24)) + "…" : preview
    }
}

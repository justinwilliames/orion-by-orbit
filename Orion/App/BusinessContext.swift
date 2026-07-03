import Foundation

/// User-supplied program context, captured once on first launch and
/// editable any time from Settings → Business context.
///
/// All fields are categorical or banded except `biggestPain` (free
/// text, capped at 200 chars). Designed to carry zero PII — no names,
/// emails, customer details. The free-text fields warn the user not to
/// paste customer data.
///
/// Persistence: JSON-encoded under `AppSettings.businessContextKey` in
/// UserDefaults. Schema version stamped in case we evolve the shape.
struct BusinessContext: Codable, Equatable {
    var vertical: String
    var espTool: String
    var primaryChannel: String
    var listSizeBand: String
    var teamSize: String
    var biggestPain: String
    var schemaVersion: Int
    var capturedAt: Date

    static let currentSchemaVersion = 1
    static let painCharacterLimit = 200

    static func empty() -> BusinessContext {
        BusinessContext(
            vertical: "",
            espTool: "",
            primaryChannel: "",
            listSizeBand: "",
            teamSize: "",
            biggestPain: "",
            schemaVersion: currentSchemaVersion,
            capturedAt: Date()
        )
    }

    /// Required fields are non-empty. `biggestPain` is optional.
    var isComplete: Bool {
        !vertical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !espTool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !primaryChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !listSizeBand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !teamSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// System-prompt fragment shaped to brief Orion without
    /// changing his persona. Empty string when not yet complete.
    func systemPromptSection() -> String {
        guard isComplete else { return "" }
        var lines: [String] = [
            "WHO YOU'RE TALKING TO RIGHT NOW",
            "User-reported program context. Treat as orientation, not gospel — could be incomplete or stale. Use it to skip beginner framing they don't need, choose the ESP-specific answer when relevant, and pick examples that match their vertical. Don't quote it back at them.",
            "",
            "- Vertical: \(vertical)",
            "- ESP / CRM tool: \(espTool)",
            "- Primary channel: \(primaryChannel)",
            "- List size: \(listSizeBand)",
            "- Team size: \(teamSize)"
        ]
        let trimmedPain = biggestPain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPain.isEmpty {
            lines.append("- Current focus / pain: \(trimmedPain)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Curated option lists for the survey pickers. Each list is shown
/// with a final "Other (specify)" row that swaps the picker for a
/// free text field. Lists are ordered roughly by expected frequency in
/// Sir's audience, not alphabetically.
enum BusinessContextOptions {
    static let verticals: [String] = [
        "Consumer SaaS",
        "B2B SaaS",
        "E-commerce / DTC",
        "Marketplace",
        "Retail",
        "Fintech / banking",
        "Insurance",
        "Health / wellness",
        "Media / publishing",
        "Education / edtech",
        "Travel / hospitality",
        "Food / restaurant / delivery",
        "Gaming",
        "Creator economy",
        "Non-profit",
        "Real estate / proptech",
        "Telecom",
        "Government / public sector",
        "Professional services / agency"
    ]

    static let espTools: [String] = [
        "Braze",
        "Iterable",
        "Customer.io",
        "HubSpot",
        "Klaviyo",
        "Mailchimp",
        "Salesforce Marketing Cloud",
        "Marketo",
        "Pardot",
        "Intercom",
        "ActiveCampaign",
        "SendGrid / Twilio",
        "Brevo (Sendinblue)",
        "ConvertKit / Kit",
        "Constant Contact",
        "Drip",
        "Omnisend",
        "Attentive",
        "Postscript",
        "OneSignal",
        "Built in-house",
        "None yet"
    ]

    static let channels: [String] = [
        "Email primarily",
        "Push primarily",
        "SMS primarily",
        "In-app primarily",
        "Multi-channel"
    ]

    static let listSizeBands: [String] = [
        "Under 10k",
        "10k–100k",
        "100k–1M",
        "1M+"
    ]

    static let teamSizes: [String] = [
        "Just me",
        "2–5",
        "6–20",
        "20+"
    ]
}

import Foundation

/// Durable fact Orion remembers about Sir between conversations.
///
/// Stored as a single JSON file per entry on disk. The body is the
/// load-bearing field — it's what gets spliced into Orion's
/// system prompt when retrieved. Name and description are for the
/// Settings UI: name is the headline, description is the one-line
/// hook shown alongside the body.
///
/// Five flavours, mirroring the global Claude memory system:
///
///   - .user         The user's role, preferences, working style.
///   - .feedback     Corrections / confirmations Sir has given.
///   - .project      Active work, deadlines, ongoing initiatives.
///   - .reference    Pointers to external systems or canonical sources.
///   - .preference   Standing taste calls (e.g. "always lead with the
///                   uncomfortable observation, then the framework").
///
/// Sensitivity is filtered at write time by `SensitivityFilter` —
/// entries containing PII / secrets are rejected before they reach
/// the store.
struct MemoryEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case user
        case feedback
        case project
        case reference
        case preference

        var label: String {
            switch self {
            case .user: return "User"
            case .feedback: return "Feedback"
            case .project: return "Project"
            case .reference: return "Reference"
            case .preference: return "Preference"
            }
        }

        var sortOrder: Int {
            switch self {
            case .user: return 0
            case .preference: return 1
            case .feedback: return 2
            case .project: return 3
            case .reference: return 4
            }
        }
    }

    let id: UUID
    var name: String
    var description: String
    var body: String
    var kind: Kind
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
    var schemaVersion: Int

    static let currentSchemaVersion = 1

    /// Hard ceilings to keep prompt budget predictable. Anything bigger
    /// either gets trimmed (body) or rejected at extraction time.
    static let nameCharLimit        = 80
    static let descriptionCharLimit = 200
    static let bodyCharLimit        = 800

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        body: String,
        kind: Kind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinned: Bool = false,
        schemaVersion: Int = MemoryEntry.currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.body = body
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.schemaVersion = schemaVersion
    }

    /// Concatenated form used for embedding-similarity scoring at
    /// retrieval time. Title and description weigh as much as body
    /// here intentionally — short well-titled memories shouldn't lose
    /// to long rambling ones.
    var embeddableText: String {
        "\(name). \(description). \(body)"
    }

    /// One-line rendering for the system prompt block. Pinned entries
    /// get a leading marker so the model knows they're sticky.
    func promptLine() -> String {
        let prefix = pinned ? "★ " : "- "
        return "\(prefix)\(name): \(body)"
    }
}

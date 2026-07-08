import Foundation

/// Deterministic, local, keyword-based classifier for the MCP upsell
/// card (see MCPUpsellCardView). No network call, no LLM — just a
/// cheap pass over the just-asked question and the rendered answer.
///
/// Priority when multiple categories match: LIMIT > BUILD > DEEP-WORK.
/// `.none` means no card should render for this turn.
enum MCPUpsellMoment {
    case build
    case deepWork
    case limit
}

enum MCPUpsellTrigger {

    /// BUILD moment — the user asked for an artifact (email, template,
    /// subject lines, HTML, etc.) that Claude-with-the-MCP could produce
    /// directly instead of describing.
    static let buildKeywords: Set<String> = [
        "write", "draft", "build", "create", "template",
        "subject line", "email copy", "canvas", "segment", "html"
    ]

    /// DEEP-WORK moment — the question is a whole workflow (audit, plan,
    /// program), not a single answer.
    static let deepWorkKeywords: Set<String> = [
        "audit", "plan", "program", "win-back", "onboarding flow",
        "qa", "pre-launch", "migrate", "end-to-end", "workflow"
    ]

    /// LIMIT moment — the user is asking for something the free Mac app
    /// literally cannot do (live data, connectors, generated files).
    static let limitKeywords: Set<String> = [
        "connect", "push", "export", "publish", "sync", "upload",
        "generate a file", "my braze", "our braze", "live data"
    ]

    /// Phrases that indicate the assistant's own answer admitted an
    /// inability/limitation — this alone is enough to trigger LIMIT
    /// even if the question itself didn't match a limit keyword.
    static let apologyPhrases: [String] = [
        "i can't", "i cant", "i'm not able to", "im not able to",
        "don't have access", "dont have access"
    ]

    /// Classify the just-completed turn. `question` is the user's most
    /// recent message; `answer` is the assistant's finished response
    /// text (post-streaming, markdown source is fine — matching is
    /// substring/keyword based and case-insensitive).
    static func classify(question: String, answer: String) -> MCPUpsellMoment? {
        let q = question.lowercased()
        let a = answer.lowercased()

        let matchesLimit = limitKeywords.contains { q.contains($0) }
            || apologyPhrases.contains { a.contains($0) }
        if matchesLimit { return .limit }

        if buildKeywords.contains(where: { q.contains($0) }) { return .build }

        if deepWorkKeywords.contains(where: { q.contains($0) }) { return .deepWork }

        return nil
    }
}

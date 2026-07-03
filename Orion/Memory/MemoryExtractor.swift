import Foundation

/// Runs after each substantive turn. Fires a one-shot model call that
/// asks the connected provider to identify 0–2 durable facts worth
/// remembering from the latest exchange, runs each candidate through
/// `SensitivityFilter`, and saves the survivors via `MemoryStore`.
///
/// Goals:
///   - **Compounding value.** Every conversation should make the next
///     one slightly sharper without Sir having to type "remember…".
///   - **Sensitive-data hygiene.** Both the prompt and a Swift-side
///     regex filter conspire to keep PII / secrets / financial precision
///     out of long-term storage.
///   - **Cheap.** Spawned subprocess (Claude or Codex CLI), bounded
///     timeout, silent fallback on failure. No effect on chat latency
///     because extraction runs on a background queue after the user's
///     turn has already been delivered.
///
/// Skipped on:
///   - User toggled "auto-extract memories" off in Settings.
///   - The exchange is chitchat (under 40 chars combined or no
///     assistant content).
///   - Neither Claude Code nor Codex CLI is installed.
enum MemoryExtractor {

    /// Notification fired with `userInfo: ["memory": MemoryEntry]` when
    /// a candidate clears the sensitivity filter and lands on disk.
    /// Surfaces for an inline "remembered: X" toast (built later).
    static let didExtractNotification = Notification.Name("OrionMemoryExtractorDidExtract")

    /// Notification fired when extraction starts, finishes (success or
    /// failure), or is skipped. Useful for debug tooling. Object is the
    /// `Phase` value below.
    static let didChangePhaseNotification = Notification.Name("OrionMemoryExtractorDidChangePhase")

    enum Phase: Equatable {
        case skipped(reason: String)
        case running
        case finished(savedCount: Int)
        case failed(reason: String)
    }

    /// Fire-and-forget. Always returns immediately on the calling
    /// thread; the actual work happens on a background queue.
    static func extract(
        userMessage: String,
        assistantReply: String,
        priorMemoryDigest: String? = nil
    ) {
        guard AppSettings.autoExtractMemoryEnabled else {
            post(.skipped(reason: "auto-extract disabled"))
            return
        }

        let userTrimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyTrimmed = assistantReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replyTrimmed.isEmpty, (userTrimmed.count + replyTrimmed.count) >= 40 else {
            post(.skipped(reason: "exchange too short"))
            return
        }

        // Pick a CLI we can spawn for a one-shot call. Prefer Claude,
        // fall back to Codex. If neither, skip silently — OpenAI API
        // users get no auto-extraction in v1.
        let cli: (path: String, label: String)?
        if let claude = AppSettings.resolveExecutablePath(named: "claude") {
            cli = (claude, "claude")
        } else if let codex = AppSettings.resolveExecutablePath(named: "codex") {
            cli = (codex, "codex")
        } else {
            cli = nil
        }
        guard let cli else {
            post(.skipped(reason: "no CLI available"))
            return
        }

        post(.running)

        DispatchQueue.global(qos: .utility).async {
            let prompt = buildExtractionPrompt(
                userMessage: userTrimmed,
                assistantReply: replyTrimmed,
                priorMemoryDigest: priorMemoryDigest
            )
            let raw = runOneShot(cli: cli, prompt: prompt)
            guard let raw, !raw.isEmpty else {
                post(.failed(reason: "no output from \(cli.label)"))
                return
            }

            let candidates = parseCandidates(from: raw)
            var saved = 0
            for candidate in candidates {
                let entry = candidate.toMemoryEntry()
                let decision = MemoryStore.save(entry)
                switch decision {
                case .allow:
                    saved += 1
                    NotificationCenter.default.post(
                        name: didExtractNotification,
                        object: nil,
                        userInfo: ["memory": entry]
                    )
                case .reject(let reason):
                    SessionDebugLogger.log("memory", "rejected candidate \"\(entry.name)\" — \(reason)")
                }
            }
            post(.finished(savedCount: saved))
        }
    }

    // MARK: - Prompt

    private static func buildExtractionPrompt(
        userMessage: String,
        assistantReply: String,
        priorMemoryDigest: String?
    ) -> String {
        let priorBlock = (priorMemoryDigest?.isEmpty == false)
            ? "\nALREADY KNOWN ABOUT THE USER (don't restate any of these; only add NEW facts):\n\(priorMemoryDigest!)\n"
            : ""

        return """
        You are extracting durable facts about a CRM/lifecycle marketing operator from their last conversation turn, for long-term memory used by Orion (a desktop companion that grounds future answers in remembered context).

        Read the exchange below. Output JSON listing 0–2 facts worth remembering for future conversations. Quality > quantity. If nothing about this turn is worth remembering, return an empty list.

        STRICT REQUIREMENTS — non-negotiable:
        - NEVER include: specific names of customers, employees, contacts, or vendors; email addresses; phone numbers; exact revenue, LTV, CAC, or any precise financial figure; customer/segment IDs; API keys; passwords; addresses; anything that looks like authentication.
        - GENERALISE specifics. "~500K subscribers" not "487,213". "consumer marketplace" not "AcmeMart Inc." "low-hundreds CAC" not "$143.27".
        - Skip pure chitchat, debugging questions, factual lookups, or one-off how-to questions.
        - Only extract when the fact tells you something durable about who the user is, what they're working on, what they prefer, or what tools/systems they reference.

        EVALUATION CRITERIA — extract only when ALL hold:
        1. The fact is TRUE (the user said it or it's clearly implied).
        2. It would help someone walking into this conversation 6 months from now.
        3. It is NOT already covered by what's already known about the user.
        4. It does NOT contain any of the restricted categories above.

        FACT KIND — choose one per fact:
        - user        Role, expertise, working style.
        - feedback    A correction or confirmation about how to communicate with them.
        - project     Active work, deadlines, an initiative they're driving.
        - reference   A pointer to an external system or canonical source they use.
        - preference  A standing taste call about answers (length, depth, tone).

        OUTPUT FORMAT — return ONLY valid JSON, no prose, no code fences:
        {
          "memories": [
            {
              "kind": "user|feedback|project|reference|preference",
              "name": "<short headline, ~6–10 words>",
              "description": "<one-line hook for the Settings UI>",
              "body": "<1–3 sentences, the durable fact itself, generalised>"
            }
          ]
        }
        \(priorBlock)
        EXCHANGE TO EVALUATE:

        USER MESSAGE:
        \(userMessage)

        ASSISTANT REPLY:
        \(assistantReply)
        """
    }

    // MARK: - Subprocess

    private static func runOneShot(cli: (path: String, label: String), prompt: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cli.path)
        task.arguments = ["-p", prompt]
        task.environment = ProcessInfo.processInfo.environment
        task.currentDirectoryURL = AppSettings.cliWorkingDirectoryURL()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(45)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if task.isRunning {
            task.terminate()
            return nil
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Parsing

    private struct ExtractionCandidate: Decodable {
        let kind: String
        let name: String
        let description: String
        let body: String

        func toMemoryEntry() -> MemoryEntry {
            let resolvedKind = MemoryEntry.Kind(rawValue: kind.lowercased()) ?? .user
            return MemoryEntry(
                name: name,
                description: description,
                body: body,
                kind: resolvedKind
            )
        }
    }

    private struct ExtractionPayload: Decodable {
        let memories: [ExtractionCandidate]
    }

    private static func parseCandidates(from raw: String) -> [ExtractionCandidate] {
        // Pull out the first balanced { ... } block — most CLIs prepend
        // status lines or wrap in code fences despite the "no fences"
        // instruction.
        guard let jsonString = extractFirstJSONObject(in: raw),
              let data = jsonString.data(using: .utf8) else {
            return []
        }
        do {
            let payload = try JSONDecoder().decode(ExtractionPayload.self, from: data)
            return payload.memories
        } catch {
            return []
        }
    }

    private static func extractFirstJSONObject(in text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = firstBrace
        while index < text.endIndex {
            let ch = text[index]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let endIndex = text.index(after: index)
                    return String(text[firstBrace..<endIndex])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Notification helper

    private static func post(_ phase: Phase) {
        NotificationCenter.default.post(name: didChangePhaseNotification, object: phase)
    }
}

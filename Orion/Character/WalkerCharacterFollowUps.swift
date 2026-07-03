import AppKit
import Foundation

extension WalkerCharacter {
    /// Spawn a one-shot Claude CLI call to generate two short follow-up
    /// suggestions based on the most recent assistant turn. Behaviour
    /// mirrors `generateAmbientLineViaLLM` in WalkerCharacterBubble:
    /// background queue, 25s deadline, cwd pinned to the Orion temp
    /// dir so we don't trigger TCC prompts in the user's home folders.
    ///
    /// Result is delivered on the main queue. Callers must defensively
    /// handle:
    ///   - `nil` (CLI not available, parse failure, deadline)
    ///   - empty array (LLM returned no usable lines)
    ///   - 1 entry (we asked for 2 but the model only delivered one)
    ///
    /// Two reasons we don't try harder:
    ///   - Follow-ups are entirely additive; missing them is invisible.
    ///   - The user hates re-prompts. If the spawn fails, drop it
    ///     silently rather than retrying.
    func generateFollowUpSuggestions(
        userMessage: String,
        assistantReply: String,
        completion: @escaping ([String]) -> Void
    ) {
        guard let claudePath = AppSettings.resolveExecutablePath(named: "claude") else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        // Trim heavily — the prompt only needs the gist of the last
        // exchange. The model produces sharper follow-ups when given
        // tight context rather than a wall of markdown.
        let trimmedUser = String(userMessage.prefix(400))
        let trimmedAssistant = String(assistantReply.prefix(900))

        let prompt = """
        You are Orion's follow-up suggester. Given the conversation excerpt below, output exactly TWO short follow-up questions the user might ask next, in their voice. Each ≤ 7 words. Practical and specific to the topic — not generic ("Tell me more"). Output ONLY a JSON array of two strings, no prose, no code fences, no surrounding quotes inside the strings.

        User asked: \(trimmedUser)

        Orion replied: \(trimmedAssistant)

        Output:
        """

        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: claudePath)
            task.arguments = ["-p", prompt]
            task.environment = ProcessInfo.processInfo.environment
            // Same cwd discipline as the ambient bubble path. See
            // AppSettings.cliWorkingDirectoryURL() for full rationale.
            task.currentDirectoryURL = AppSettings.cliWorkingDirectoryURL()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            do {
                try task.run()
            } catch {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let deadline = Date().addingTimeInterval(25)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if task.isRunning {
                task.terminate()
                DispatchQueue.main.async { completion([]) }
                return
            }

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            let parsed = WalkerCharacter.parseFollowUpResponse(raw)
            DispatchQueue.main.async { completion(parsed) }
        }
    }

    /// Lenient parser. Tries strict JSON array first; falls back to
    /// extracting double-quoted lines from anywhere in the output. Some
    /// model paths wrap the JSON in code fences or add a "Output:"
    /// preamble — both shapes are normalised here.
    static func parseFollowUpResponse(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pluck the first balanced JSON array, if present. Defensive
        // against models that wrap output in ```json ... ``` fences.
        if let arrayStart = trimmed.firstIndex(of: "["),
           let arrayEnd = trimmed.lastIndex(of: "]"),
           arrayStart < arrayEnd {
            let candidate = String(trimmed[arrayStart...arrayEnd])
            if let data = candidate.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
                return cleanFollowUpStrings(parsed)
            }
        }

        // Fall back: scan for any double-quoted strings on their own
        // lines. Catches the case where the model emits a numbered list
        // instead of JSON. Still bounded — return at most 2.
        var fallback: [String] = []
        let lines = trimmed.split(whereSeparator: \.isNewline)
        for line in lines {
            let lineStr = String(line)
            if let quotedStart = lineStr.firstIndex(of: "\""),
               let quotedEnd = lineStr.lastIndex(of: "\""),
               quotedStart < quotedEnd {
                let inner = String(lineStr[lineStr.index(after: quotedStart)..<quotedEnd])
                if !inner.isEmpty { fallback.append(inner) }
            }
        }
        return cleanFollowUpStrings(fallback)
    }

    private static func cleanFollowUpStrings(_ candidates: [String]) -> [String] {
        let cleaned: [String] = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 80 }
        // Plain Array(_:Sequence) avoids the .prefix(_:)/.prefix(while:)
        // overload ambiguity that swift-build hit on the chained form.
        return Array(cleaned.prefix(2))
    }

    /// Inspect the most recent exchange and, if it warrants follow-ups,
    /// kick off the generation. Designed to be fire-and-forget from
    /// `onTurnComplete`. Three guards keep this honest:
    ///   1. Skip when an expert is focused — those flows render their
    ///      own suggestion UI (the upstream Lenny pattern).
    ///   2. Skip if the assistant's reply is too short (< 40 words).
    ///      Chitchat ("got it", "thanks") doesn't deserve a follow-up.
    ///   3. Skip if there's nothing useful to seed against (no user
    ///      message immediately preceding the assistant turn).
    func scheduleFollowUpGeneration() {
        guard focusedExpert == nil else { return }
        guard let session = claudeSession else { return }

        let history = session.history(for: nil)

        // Find the last assistant message and walk back from that index
        // to the most recent user message that preceded it — the pair
        // we want to feed the follow-up generator. Index-based rather
        // than reference-based since Message is a value type.
        guard let lastAssistantIndex = history.lastIndex(where: { $0.role == .assistant }) else { return }
        let beforeAssistant = history.prefix(lastAssistantIndex)
        guard let lastUser = beforeAssistant.reversed().first(where: { $0.role == .user }) else { return }

        let assistantText = history[lastAssistantIndex].text
        let wordCount = assistantText.split { $0.isWhitespace }.count
        guard wordCount >= 40 else { return }

        let userText = lastUser.text
        let assistantSnapshot = assistantText

        generateFollowUpSuggestions(
            userMessage: userText,
            assistantReply: assistantSnapshot
        ) { [weak self] suggestions in
            guard let self else { return }
            // Re-validate guards on response. The user may have closed
            // the popover, sent another message, or cleared the
            // conversation while the LLM call was in flight — in any
            // of those cases the chips are no longer relevant.
            guard suggestions.count > 0 else { return }
            guard let terminal = self.terminalView else { return }
            // If the user already typed something, don't shove chips
            // onto a transcript they're moving past.
            if !terminal.inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            // History changed under us — the message we generated
            // against is no longer the latest exchange.
            if let currentHistory = self.claudeSession?.history(for: nil),
               currentHistory.last(where: { $0.role == .assistant })?.text != assistantSnapshot {
                return
            }

            terminal.showFollowUpChips(suggestions) { chipText in
                terminal.inputField.stringValue = chipText
                terminal.clearFollowUpChips()
                terminal.inputSubmitted()
            }
        }
    }
}

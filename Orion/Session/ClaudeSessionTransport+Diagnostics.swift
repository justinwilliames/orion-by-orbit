import Foundation

extension ClaudeSession {
    func preferredWorkingDirectoryURL() -> URL {
        // Delegates to AppSettings.cliWorkingDirectoryURL() so the chat
        // path and the ambient-bubble path share a single source of
        // truth for the spawned CLI's cwd. See the doc on the
        // AppSettings helper for the full rationale.
        AppSettings.cliWorkingDirectoryURL()
    }

    func logStartupDiagnostics() {
        Task.detached(priority: .utility) {
            let processEnv = ProcessInfo.processInfo.environment

            // ── Runtimes ─────────────────────────────────────────────────────
            // hasDetectedClaudeLogin / hasDetectedCodexLogin use the full path
            // scan (nvm version scan, volta, fnm, etc.) — more accurate than
            // checking ProcessInfo.processInfo.environment["PATH"] directly.
            let claudeLoggedIn = AppSettings.hasDetectedClaudeLogin
            let codexLoggedIn  = AppSettings.hasDetectedCodexLogin

            // Quick PATH-based check for display; falls back to login state
            let claudePathFast = self.executablePath(named: "claude", environment: processEnv)
            let codexPathFast  = self.executablePath(named: "codex",  environment: processEnv)
            let claudeFound = claudeLoggedIn || claudePathFast != nil
            let codexFound  = codexLoggedIn  || codexPathFast  != nil

            let anthropicKey     = AppSettings.hasDetectedAnthropicAPIKey
            let openaiKey        = AppSettings.hasDetectedOpenAIAPIKey

            let preferredTransport  = AppSettings.preferredTransport

            // ── Print ────────────────────────────────────────────────────────
            var lines: [String] = []
            lines.append("╔══════════════════════════════════════════════════╗")
            lines.append("║           Orion startup diagnostics          ║")
            lines.append("╚══════════════════════════════════════════════════╝")

            lines.append("")
            lines.append("── Runtimes ────────────────────────────────────────")
            lines.append("  claude  executable : \(claudeFound ? (claudePathFast ?? "found (via full scan)") : "NOT FOUND")")
            lines.append("  codex   executable : \(codexFound  ? (codexPathFast  ?? "found (via full scan)") : "NOT FOUND")")
            lines.append("  claude  logged in  : \(claudeLoggedIn ? "YES" : "NO")\(anthropicKey ? " (via ANTHROPIC_API_KEY)" : "")")
            lines.append("  codex   logged in  : \(codexLoggedIn  ? "YES" : "NO")\(openaiKey    ? " (via OPENAI_API_KEY)"    : "")")

            lines.append("")
            lines.append("── API Keys ────────────────────────────────────────")
            lines.append("  ANTHROPIC_API_KEY         : \(anthropicKey      ? "present" : "missing")")
            lines.append("  OPENAI_API_KEY            : \(openaiKey         ? "present" : "missing")")

            lines.append("")
            lines.append("── Active configuration ─────────────────────────────")
            lines.append("  Preferred transport      : \(preferredTransport.rawValue)")
            lines.append("  Claude model             : \(AppSettings.preferredClaudeModel.label)")
            lines.append("  Codex model              : \(AppSettings.preferredCodexModel.label)")
            lines.append("  OpenAI model             : \(AppSettings.preferredOpenAIModel.label)")

            lines.append("────────────────────────────────────────────────────")

            let report = lines.joined(separator: "\n")
            SessionDebugLogger.logMultiline("startup", header: "environment diagnostics", body: report)
        }
    }
}

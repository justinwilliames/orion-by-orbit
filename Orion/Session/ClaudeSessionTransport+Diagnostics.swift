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
            let fm = FileManager.default
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
            let mcpEnvToken      = !(processEnv[ClaudeSession.Constants.lennyMCPAuthEnvVar] ?? "").isEmpty
            let mcpSettingsToken = AppSettings.officialLennyMCPToken != nil

            // ── MCP in config files ──────────────────────────────────────────
            let claudeConfigURLs       = AppSettings.claudeGlobalConfigURLs
            let codexConfigURL         = AppSettings.codexGlobalConfigURL
            let claudeConfigMCPViaList = AppSettings.hasDetectedClaudeOfficialMCPConfiguration
            let codexConfigMCP         = AppSettings.containsOfficialMCPConfiguration(at: codexConfigURL)
            let codexConfigMCPViaList  = AppSettings.hasDetectedCodexOfficialMCPConfiguration

            // ── Archive mode ─────────────────────────────────────────────────
            let mcpSources          = AppSettings.detectedOfficialMCPSources
            let archiveMode         = AppSettings.effectiveArchiveAccessMode
            let preferredTransport  = AppSettings.preferredTransport
            let explicitStarterPack = AppSettings.hasExplicitStarterPackChoice

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
            lines.append("  LENNYSDATA_MCP_AUTH_TOKEN : \(mcpEnvToken       ? "present (env)"      : "missing")")
            lines.append("  Lenny MCP token (Settings): \(mcpSettingsToken  ? "present (settings)" : "missing")")

            lines.append("")
            lines.append("── Lenny MCP config detection ──────────────────────")
            for url in claudeConfigURLs {
                let exists = fm.fileExists(atPath: url.path)
                let hasMCP = AppSettings.containsOfficialMCPConfiguration(at: url)
                lines.append("  \(url.lastPathComponent.padding(toLength: 28, withPad: " ", startingAt: 0)): \(exists ? "exists" : "missing")\(hasMCP ? " ✓ has Lenny MCP" : "")")
            }
            let anyClaudeFileMCP = claudeConfigURLs.contains(where: AppSettings.containsOfficialMCPConfiguration(at:))
            if !anyClaudeFileMCP && claudeConfigMCPViaList {
                lines.append("  (claude mcp list)            : ✓ has Lenny MCP")
            }
            let codexConfigExists = fm.fileExists(atPath: codexConfigURL.path)
            lines.append("  \(codexConfigURL.lastPathComponent.padding(toLength: 28, withPad: " ", startingAt: 0)): \(codexConfigExists ? "exists" : "missing")\(codexConfigMCP ? " ✓ has Lenny MCP" : "")\((!codexConfigMCP && codexConfigMCPViaList) ? " ✓ via codex mcp list" : "")")

            lines.append("")
            lines.append("── Detected MCP sources ────────────────────────────")
            if mcpSources.isEmpty {
                lines.append("  (none)")
            } else {
                for src in mcpSources {
                    lines.append("  ✓ \(src.label)")
                }
            }

            lines.append("")
            lines.append("── Active configuration ─────────────────────────────")
            lines.append("  Preferred transport      : \(preferredTransport.rawValue)")
            lines.append("  Archive mode             : \(archiveMode.rawValue)")
            lines.append("  Explicit starter pack    : \(explicitStarterPack ? "YES (user chose Starter Pack)" : "no")")
            lines.append("  Claude model             : \(AppSettings.preferredClaudeModel.label)")
            lines.append("  Codex model              : \(AppSettings.preferredCodexModel.label)")
            lines.append("  OpenAI model             : \(AppSettings.preferredOpenAIModel.label)")

            lines.append("────────────────────────────────────────────────────")

            let report = lines.joined(separator: "\n")
            SessionDebugLogger.logMultiline("startup", header: "environment diagnostics", body: report)
        }
    }
}

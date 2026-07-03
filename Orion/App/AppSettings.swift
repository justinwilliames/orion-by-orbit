import Foundation

enum AppSettings {

    // MARK: - General config-path helpers
    //
    // Relocated from the deleted AppSettings+MCPConfig.swift. These are
    // GENERAL Claude Code / Codex CLI locators used by AppSettings+Detection
    // for login/config detection — they are NOT specific to the removed
    // official-Lenny-MCP feature, so they survive the subsystem removal.

    static var homeDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var claudeGlobalConfigURLs: [URL] {
        [
            homeDirectoryURL.appendingPathComponent(".claude.json"),
            homeDirectoryURL.appendingPathComponent(".claude/settings.json"),
            homeDirectoryURL.appendingPathComponent(".claude/settings.local.json")
        ]
    }

    static var codexGlobalConfigURL: URL {
        homeDirectoryURL.appendingPathComponent(".codex/config.toml")
    }

    /// Single source of truth for the cwd used when spawning Claude /
    /// Codex CLI subprocesses.
    ///
    /// Two reasons this lives in AppSettings rather than at each
    /// spawn site:
    ///   1. Without an explicit cwd, the spawned CLI inherits whatever
    ///      directory Orion happened to be launched in. After a
    ///      Sparkle relaunch that's often `~/Downloads` (where Finder
    ///      runs the unsigned-app open dialog) — every ambient-bubble
    ///      spawn then triggers a TCC prompt for Downloads access. Bug
    ///      shipped in v0.1.15, fixed in v0.1.24.
    ///   2. Some prompts/tool-use surfaces echo the cwd back to the
    ///      model, so the directory name needs to read as Orion —
    ///      not "Downloads" or some random temp slug.
    ///
    /// The temp dir is created on demand and lives at
    /// `$TMPDIR/OrionCLI`, which the OS cleans up periodically.
    /// The CLI doesn't store anything important there.
    static func cliWorkingDirectoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OrionCLI", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Model enums

    enum ClaudeModel: String, CaseIterable {
        case `default`
        case opus46 = "claude-opus-4-6"
        case sonnet46 = "claude-sonnet-4-6"
        case haiku45 = "claude-haiku-4-5-20251001"

        var label: String {
            switch self {
            case .default: return "Claude"
            case .opus46: return "Claude Opus 4.6"
            case .sonnet46: return "Claude Sonnet 4.6"
            case .haiku45: return "Claude Haiku 4.5"
            }
        }
    }

    enum OpenAIModel: String, CaseIterable {
        case gpt54 = "gpt-5.4"
        case gpt54Pro = "gpt-5.4-pro"
        case gpt54Mini = "gpt-5.4-mini"
        case gpt54Nano = "gpt-5.4-nano"
        case gpt41 = "gpt-4.1"
        case gpt5 = "gpt-5"
        case gpt5Mini = "gpt-5-mini"
        case gpt5Nano = "gpt-5-nano"

        var label: String {
            switch self {
            case .gpt54: return "GPT-5.4"
            case .gpt54Pro: return "GPT-5.4 Pro"
            case .gpt54Mini: return "GPT-5.4 mini"
            case .gpt54Nano: return "GPT-5.4 nano"
            case .gpt41: return "GPT-4.1"
            case .gpt5: return "GPT-5"
            case .gpt5Mini: return "GPT-5 mini"
            case .gpt5Nano: return "GPT-5 nano"
            }
        }
    }

    enum CodexModel: String, CaseIterable {
        case `default`
        case gpt54 = "gpt-5.4"
        case gpt54Mini = "gpt-5.4-mini"
        case gpt53Codex = "gpt-5.3-codex"

        var label: String {
            switch self {
            case .default: return "Codex"
            case .gpt54: return "GPT-5.4"
            case .gpt54Mini: return "GPT-5.4 mini"
            case .gpt53Codex: return "GPT-5.3 Codex"
            }
        }
    }

    enum PreferredTransport: String {
        case automatic
        case claudeCode
        case codex
        case openAIAPI
    }

    // MARK: - UserDefaults keys

    static let preferredTransportKey              = "preferredTransport"
    static let hasExplicitPreferredTransportChoiceKey = "hasExplicitPreferredTransportChoice"
    static let openAIAPIKeyKey                   = "openAIAPIKey"
    static let debugLoggingEnabledKey            = "debugLoggingEnabled"
    static let preferredClaudeModelKey           = "preferredClaudeModel"
    static let preferredCodexModelKey            = "preferredCodexModel"
    static let preferredOpenAIModelKey           = "preferredOpenAIModel"
    static let launchAtLoginKey                  = "launchAtLogin"
    static let useAmbientLLMKey                  = "useAmbientLLM"

    // MARK: - Preferences

    /// Run at login. Defaults to ON for first-install users (the menu-bar
    /// app is ambient — most users want it back after restart
    /// without thinking about it). Wired via SMAppService.mainApp; the
    /// first call to `applyLaunchAtLoginPreference()` triggers the OS
    /// permission grant in System Settings → General → Login Items.
    static var launchAtLoginEnabled: Bool {
        get {
            // If the user has never explicitly set this, default to ON.
            if UserDefaults.standard.object(forKey: launchAtLoginKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: launchAtLoginKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
        }
    }

    /// AI-generated ambient comments. When ON, Orion makes a
    /// one-shot LLM call (via the connected provider) to generate a
    /// fresh ambient bubble line every 90–240s of idle time. Falls
    /// back to a hardcoded pool if the provider call fails or no
    /// provider is connected. Default ON.
    static var useAmbientLLMEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: useAmbientLLMKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: useAmbientLLMKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: useAmbientLLMKey)
        }
    }

    static var preferredTransport: PreferredTransport {
        get {
            let rawValue = UserDefaults.standard.string(forKey: preferredTransportKey) ?? PreferredTransport.automatic.rawValue
            return PreferredTransport(rawValue: rawValue) ?? .automatic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferredTransportKey) }
    }

    static var hasExplicitPreferredTransportChoice: Bool {
        get { UserDefaults.standard.bool(forKey: hasExplicitPreferredTransportChoiceKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasExplicitPreferredTransportChoiceKey) }
    }

    static var openAIAPIKey: String? {
        get {
            let value = UserDefaults.standard.string(forKey: openAIAPIKeyKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: openAIAPIKeyKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: openAIAPIKeyKey)
            }
        }
    }

    static var debugLoggingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: debugLoggingEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: debugLoggingEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: debugLoggingEnabledKey) }
    }

    static var preferredClaudeModel: ClaudeModel {
        get {
            let rawValue = UserDefaults.standard.string(forKey: preferredClaudeModelKey) ?? ClaudeModel.default.rawValue
            return ClaudeModel(rawValue: rawValue) ?? .default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferredClaudeModelKey) }
    }

    static var preferredCodexModel: CodexModel {
        get {
            let rawValue = UserDefaults.standard.string(forKey: preferredCodexModelKey) ?? CodexModel.default.rawValue
            return CodexModel(rawValue: rawValue) ?? .default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferredCodexModelKey) }
    }

    static var preferredOpenAIModel: OpenAIModel {
        get {
            let rawValue = UserDefaults.standard.string(forKey: preferredOpenAIModelKey) ?? OpenAIModel.gpt54Mini.rawValue
            return OpenAIModel(rawValue: rawValue) ?? .gpt54Mini
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferredOpenAIModelKey) }
    }

    static var showsDeveloperTools: Bool {
        ProcessInfo.processInfo.arguments.contains("#debug")
    }

    // MARK: - Reset

    static func resetAllData() throws {
        let defaults = UserDefaults.standard
        let managedKeys = [
            preferredTransportKey,
            hasExplicitPreferredTransportChoiceKey,
            openAIAPIKeyKey,
            debugLoggingEnabledKey,
            preferredClaudeModelKey,
            preferredCodexModelKey,
            preferredOpenAIModelKey,
            "hasCompletedOnboarding"
        ]

        for key in managedKeys {
            defaults.removeObject(forKey: key)
        }

        clearBusinessContextState()
        clearMemoryLayerState()
        refreshDetectionState()
        NotificationCenter.default.post(name: .liLJustinDidResetData, object: nil)
        NotificationCenter.default.post(name: .liLJustinBusinessContextDidChange, object: nil)
        NotificationCenter.default.post(name: MemoryStore.didChangeNotification, object: nil)
    }
}

extension Notification.Name {
    static let liLJustinDidResetData = Notification.Name("OrionDidResetData")
}

// MARK: - MCP mirror from Claude Desktop → Claude Code

extension AppSettings {

    /// Result of a "Sync MCPs from Claude Desktop" attempt — surfaced
    /// to the Settings UI so the user can see what happened.
    struct MCPSyncResult {
        let added: [String]
        let skipped: [String]
        let error: String?

        var summary: String {
            if let error { return error }
            if added.isEmpty && skipped.isEmpty {
                return "No MCP servers found in Claude Desktop's config."
            }
            if added.isEmpty {
                let n = skipped.count
                return "Already up to date — \(n) MCP\(n == 1 ? "" : "s") already shared with Claude Code."
            }
            return "Mirrored \(added.count) MCP\(added.count == 1 ? "" : "s") into Claude Code: \(added.joined(separator: ", "))."
        }
    }

    private static var claudeDesktopConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    private static var claudeCodeConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
    }

    /// Read Claude Desktop's MCP server registry and ADD any missing
    /// entries to Claude Code's `~/.claude.json`. Existing Claude Code
    /// MCP entries are NEVER overwritten — same-named MCP in both
    /// configs leaves Claude Code's version untouched. The `claude`
    /// CLI (which Orion spawns for chat) reads `~/.claude.json`,
    /// so any MCP added here becomes available to Orion.
    ///
    /// Backs up `~/.claude.json` to `~/.claude.json.orion-backup`
    /// before writing. If Claude Desktop's config is missing or
    /// either file fails to parse as JSON, returns a descriptive
    /// error and leaves files untouched.
    @discardableResult
    static func mirrorClaudeDesktopMCPs() -> MCPSyncResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: claudeDesktopConfigURL.path) else {
            return MCPSyncResult(added: [], skipped: [], error: "Claude Desktop config not found. Install Claude Desktop and add at least one MCP server to it first.")
        }
        guard let desktopData = try? Data(contentsOf: claudeDesktopConfigURL),
              let desktopJSON = try? JSONSerialization.jsonObject(with: desktopData) as? [String: Any] else {
            return MCPSyncResult(added: [], skipped: [], error: "Couldn't parse Claude Desktop's config — make sure it's valid JSON.")
        }
        let desktopMCPs = (desktopJSON["mcpServers"] as? [String: Any]) ?? [:]

        // Load (or initialise) Claude Code config
        var codeJSON: [String: Any] = [:]
        if fm.fileExists(atPath: claudeCodeConfigURL.path) {
            guard let codeData = try? Data(contentsOf: claudeCodeConfigURL),
                  let parsed = try? JSONSerialization.jsonObject(with: codeData) as? [String: Any] else {
                return MCPSyncResult(added: [], skipped: [], error: "Couldn't parse ~/.claude.json — left it untouched.")
            }
            codeJSON = parsed
        }
        var codeMCPs = (codeJSON["mcpServers"] as? [String: Any]) ?? [:]

        var added: [String] = []
        var skipped: [String] = []
        for (name, config) in desktopMCPs {
            if codeMCPs[name] != nil {
                skipped.append(name)
            } else {
                codeMCPs[name] = config
                added.append(name)
            }
        }

        // Nothing new to add → no write, no backup churn.
        guard !added.isEmpty else {
            return MCPSyncResult(added: [], skipped: skipped, error: nil)
        }

        // Backup existing Code config before mutating.
        if fm.fileExists(atPath: claudeCodeConfigURL.path) {
            let backupURL = claudeCodeConfigURL.appendingPathExtension("orion-backup")
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: claudeCodeConfigURL, to: backupURL)
        }

        codeJSON["mcpServers"] = codeMCPs
        guard let merged = try? JSONSerialization.data(withJSONObject: codeJSON, options: [.prettyPrinted, .sortedKeys]) else {
            return MCPSyncResult(added: [], skipped: skipped, error: "Couldn't serialise merged config — left ~/.claude.json untouched.")
        }
        do {
            try merged.write(to: claudeCodeConfigURL)
            NSLog("[Orion] Mirrored \(added.count) MCPs from Claude Desktop: \(added.joined(separator: ", "))")
            return MCPSyncResult(added: added, skipped: skipped, error: nil)
        } catch {
            return MCPSyncResult(added: [], skipped: skipped, error: "Couldn't write ~/.claude.json: \(error.localizedDescription)")
        }
    }
}

// MARK: - Launch at login (SMAppService)

import ServiceManagement

extension AppSettings {

    /// Reconcile the OS login-item registration with the stored
    /// `launchAtLoginEnabled` preference. Called once at app launch,
    /// and again whenever the user toggles the setting.
    ///
    /// First call after install will register the app with the OS,
    /// which triggers macOS to surface a System Settings → General
    /// → Login Items prompt for the user to approve.
    static func applyLaunchAtLoginPreference() {
        let service = SMAppService.mainApp
        let want = launchAtLoginEnabled
        do {
            switch service.status {
            case .enabled:
                if !want { try service.unregister() }
            case .notRegistered, .notFound:
                if want { try service.register() }
            case .requiresApproval:
                // User has the registration but hasn't approved it yet
                // in System Settings. Nothing we can force from here —
                // the OS handles the prompt. Keep our preference in
                // sync so a re-toggle in our UI still works.
                break
            @unknown default:
                if want { try service.register() }
            }
        } catch {
            NSLog("[Orion] Launch-at-login update failed: \(error.localizedDescription)")
        }
    }
}

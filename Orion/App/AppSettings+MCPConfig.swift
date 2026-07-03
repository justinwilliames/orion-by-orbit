import Foundation

extension AppSettings {
    private static let officialMCPMarkers = [
        "https://mcp.lennysdata.com/mcp",
        "lennysdata"
    ]

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

    static func containsOfficialMCPConfiguration(at url: URL) -> Bool {
        if url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) else {
                return false
            }
            return containsOfficialClaudeMCPConfiguration(in: root)
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        let lowered = contents.lowercased()
        return officialMCPMarkers.allSatisfy { lowered.contains($0.lowercased()) }
    }

    static func shellEnvironmentOfficialMCPToken() -> String? {
        let environment = resolveShellEnvironment()
        let token = environment[shellEnvironmentMCPTokenKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    static func removeOfficialMCPConfiguration() throws {
        for url in claudeGlobalConfigURLs {
            try removeClaudeOfficialMCPConfiguration(at: url)
        }
        try removeCodexOfficialMCPConfiguration(at: codexGlobalConfigURL)
    }

    private static func removeClaudeOfficialMCPConfiguration(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let existingData = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] else { return }
        guard let cleanedRoot = removeOfficialClaudeMCPConfiguration(from: root) as? [String: Any] else { return }

        try writeJSONObject(cleanedRoot, to: url)
    }

    private static func removeCodexOfficialMCPConfiguration(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let existing = try String(contentsOf: url, encoding: .utf8)
        let normalized = existing.replacingOccurrences(of: "\r\n", with: "\n")
        let pattern = #"(?ms)^\[mcp_servers\.lennysdata(?:\..+)?\]\n.*?(?=^\[(?!mcp_servers\.lennysdata(?:[.\]]|$)).*|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let cleaned = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        try writeTextConfig(cleaned.hasSuffix("\n") ? cleaned : cleaned + "\n", to: url)
    }

    static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    static func writeTextConfig(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - JSON MCP entry matching

    private static func containsOfficialClaudeMCPConfiguration(in value: Any) -> Bool {
        if isOfficialClaudeMCPServerConfiguration(value) {
            return true
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsOfficialClaudeMCPConfiguration(in:))
        }

        if let array = value as? [Any] {
            return array.contains(where: containsOfficialClaudeMCPConfiguration(in:))
        }

        return false
    }

    private static func removeOfficialClaudeMCPConfiguration(from value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            var cleaned: [String: Any] = [:]

            for (key, childValue) in dictionary {
                if isOfficialClaudeMCPEntry(key: key, value: childValue) {
                    continue
                }

                guard let cleanedChild = removeOfficialClaudeMCPConfiguration(from: childValue) else {
                    continue
                }

                if key == "mcpServers",
                   let servers = cleanedChild as? [String: Any],
                   servers.isEmpty {
                    continue
                }

                cleaned[key] = cleanedChild
            }

            return cleaned
        }

        if let array = value as? [Any] {
            return array.compactMap { element -> Any? in
                if let string = element as? String, isOfficialClaudeMCPPermission(string) {
                    return nil
                }
                return removeOfficialClaudeMCPConfiguration(from: element)
            }
        }

        return value
    }

    private static func isOfficialClaudeMCPEntry(key: String, value: Any) -> Bool {
        if isOfficialClaudeMCPServerConfiguration(value) {
            return true
        }

        return key.caseInsensitiveCompare(ClaudeSession.Constants.lennyMCPServerLabel) == .orderedSame
    }

    private static func isOfficialClaudeMCPServerConfiguration(_ value: Any) -> Bool {
        guard let dictionary = value as? [String: Any],
              let url = dictionary["url"] as? String else {
            return false
        }

        return url.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(ClaudeSession.Constants.lennyMCPURL) == .orderedSame
    }

    private static func isOfficialClaudeMCPPermission(_ value: String) -> Bool {
        value.lowercased().hasPrefix("mcp__\(ClaudeSession.Constants.lennyMCPServerLabel.lowercased())__")
    }
}

import Foundation

extension AppSettings {
    private static var cachedShellEnvironment: [String: String]?
    private static var cachedClaudeLogin: Bool?
    private static var cachedCodexLogin: Bool?

    static var hasDetectedCodexLogin: Bool {
        if let cached = cachedCodexLogin { return cached }
        let result = detectCodexLogin()
        cachedCodexLogin = result
        return result
    }

    private static func detectCodexLogin() -> Bool {
        guard executablePathForDetection(named: "codex") != nil else { return false }
        if hasDetectedOpenAIAPIKey { return true }
        if hasDetectedCodexAuthFile { return true }

        guard let executable = executablePathForDetection(named: "codex") else { return false }
        let result = runCommand(executablePath: executable, arguments: ["login", "status"])
        guard result.status == 0 else { return false }

        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        if output.contains("not logged in") || output.contains("login required") {
            return false
        }
        if output.contains("logged in") || output.contains("chatgpt") || output.contains("openai") {
            return true
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Codex stores its auth in ~/.codex/auth.json — if it exists with content, the user is authenticated.
    static var hasDetectedCodexAuthFile: Bool {
        let authPath = homeDirectoryURL.appendingPathComponent(".codex/auth.json").path
        guard let data = FileManager.default.contents(atPath: authPath),
              !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        // Any of these keys mean the user authenticated at some point
        return json["OPENAI_API_KEY"] != nil || json["tokens"] != nil || json["token"] != nil || json["api_key"] != nil
    }

    static var hasDetectedClaudeLogin: Bool {
        if let cached = cachedClaudeLogin { return cached }
        let result = detectClaudeLogin()
        cachedClaudeLogin = result
        return result
    }

    private static func detectClaudeLogin() -> Bool {
        guard let executable = executablePathForDetection(named: "claude") else { return false }
        if hasDetectedAnthropicAPIKey { return true }
        let result = runCommand(executablePath: executable, arguments: ["auth", "status"])
        if let data = result.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let loggedIn = json["loggedIn"] as? Bool {
            return loggedIn
        }
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        if output.contains("not logged in") || output.contains("login required") {
            return false
        }
        return result.status == 0
    }

    static func refreshDetectionState() {
        cachedShellEnvironment = nil
        cachedClaudeLogin = nil
        cachedCodexLogin = nil
    }

    /// Clears all detection caches and repopulates them synchronously (blocks the caller).
    /// Always call on a background thread — never on the main thread.
    /// Use this when you need to know caches are warm before updating the UI.
    static func refreshAndPrefetchDetectionStateSync() {
        refreshDetectionState()
        _ = resolveShellEnvironment()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            cachedClaudeLogin = detectClaudeLogin()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            cachedCodexLogin = detectCodexLogin()
            group.leave()
        }
        group.wait()
    }

    /// Warms up all detection caches on a background thread so results are ready
    /// before the user opens Settings or the welcome panel.
    static func prefetchDetectionState() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Shell env first — login checks depend on it
            _ = resolveShellEnvironment()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                cachedClaudeLogin = detectClaudeLogin()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                cachedCodexLogin = detectCodexLogin()
                group.leave()
            }
            group.wait()
        }
    }

    static var hasDetectedOpenAIAPIKey: Bool {
        if let key = openAIAPIKey, !key.isEmpty {
            return true
        }
        let envValue = resolveShellEnvironment()["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return envValue?.isEmpty == false
    }

    static var hasDetectedAnthropicAPIKey: Bool {
        let envValue = resolveShellEnvironment()["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return envValue?.isEmpty == false
    }

    // MARK: - Shell environment

    static func resolveShellEnvironment() -> [String: String] {
        if let cachedShellEnvironment {
            return cachedShellEnvironment
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-i", "-c", "echo '---ENV_START---' && env && echo '---ENV_END---'"]
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            cachedShellEnvironment = [:]
            return [:]
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        var environment: [String: String] = [:]

        if let startRange = output.range(of: "---ENV_START---\n"),
           let endRange = output.range(of: "\n---ENV_END---") {
            let envString = String(output[startRange.upperBound..<endRange.lowerBound])
            for line in envString.components(separatedBy: "\n") {
                guard let eqRange = line.range(of: "=") else { continue }
                let key = String(line[..<eqRange.lowerBound])
                let value = String(line[eqRange.upperBound...])
                environment[key] = value
            }
        }

        cachedShellEnvironment = environment
        return environment
    }

    // MARK: - Executable path detection

    /// Public path resolver — tries PATH, shell-resolved PATH, then a
    /// short list of well-known install locations. Used by ambient-
    /// bubble LLM dispatch to find the `claude` (or `codex`) binary
    /// without spinning up the full session machinery.
    static func resolveExecutablePath(named name: String) -> String? {
        executablePathForDetection(named: name)
    }

    private static func executablePathForDetection(named name: String) -> String? {
        // 1. Try the app process PATH first (fast, works if nvm is active in the environment)
        if let rawPath = ProcessInfo.processInfo.environment["PATH"],
           let path = executablePathForDetection(named: name, rawPath: rawPath) {
            return path
        }

        // 2. Try the full shell-resolved PATH (catches nvm, volta, fnm, etc. via ~/.zshrc)
        let shellPath = resolveShellEnvironment()["PATH"] ?? ""
        if !shellPath.isEmpty, let path = executablePathForDetection(named: name, rawPath: shellPath) {
            return path
        }

        // 3. Try well-known hardcoded locations
        let home = homeDirectoryURL.path
        var fallbackPaths: [String]
        switch name {
        case "claude":
            fallbackPaths = [
                "\(home)/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ]
        case "codex":
            fallbackPaths = [
                "\(home)/.local/bin/codex",
                "\(home)/.volta/bin/codex",
                "\(home)/.npm-global/bin/codex",
                "\(home)/node_modules/.bin/codex",
                "\(home)/.nvm/versions/node/current/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/usr/local/lib/node_modules/.bin/codex"
            ]
            // Scan all nvm node versions (newest first) in case "current" symlink doesn't exist
            let nvmNodeDir = "\(home)/.nvm/versions/node"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmNodeDir) {
                let sorted = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
                for version in sorted {
                    fallbackPaths.append("\(nvmNodeDir)/\(version)/bin/codex")
                }
            }
            // Scan fnm node versions
            let fnmNodeDir = "\(home)/.fnm/node-versions"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: fnmNodeDir) {
                let sorted = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
                for version in sorted {
                    fallbackPaths.append("\(fnmNodeDir)/\(version)/installation/bin/codex")
                }
            }
        default:
            fallbackPaths = []
        }

        if let path = fallbackPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        // 4. Last resort: ask the login shell directly
        return executablePathFromLoginShellForDetection(named: name)
    }

    private static func executablePathForDetection(named name: String, rawPath: String) -> String? {
        for directory in rawPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func executablePathFromLoginShellForDetection(named name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v \(name)"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (output?.isEmpty == false) ? output : nil
    }

    static func runCommand(executablePath: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, out, err)
    }
}

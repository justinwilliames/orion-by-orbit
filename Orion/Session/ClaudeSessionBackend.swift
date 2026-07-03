import Foundation

extension ClaudeSession {
    private var shellEnvironmentCacheLifetime: TimeInterval { 5 }

    func resolveOpenAIKey(completion: @escaping (String?) -> Void) {
        resolveShellEnvironment { environment in
            completion(environment["OPENAI_API_KEY"])
        }
    }

    func resolveShellEnvironment(completion: @escaping ([String: String]) -> Void) {
        if let cached = Self.shellEnvironment,
           let resolvedAt = Self.shellEnvironmentResolvedAt,
           Date().timeIntervalSince(resolvedAt) < shellEnvironmentCacheLifetime {
            Self.openAIKey = cached["OPENAI_API_KEY"]
            SessionDebugLogger.log("env", "using cached shell environment: \(SessionDebugLogger.summarizeEnvironment(cached))")
            completion(cached)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-i", "-c", "echo '---ENV_START---' && env && echo '---ENV_END---'"]
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        proc.terminationHandler = { _ in
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
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

                // Settings key always takes priority over the shell environment.
                if let storedKey = AppSettings.openAIAPIKey, !storedKey.isEmpty {
                    environment["OPENAI_API_KEY"] = storedKey
                    SessionDebugLogger.log("env", "using locally stored OPENAI_API_KEY from Settings (overrides shell env)")
                }

                Self.shellEnvironment = environment
                Self.shellEnvironmentResolvedAt = Date()
                Self.openAIKey = environment["OPENAI_API_KEY"]
                SessionDebugLogger.log("env", "resolved shell environment: \(SessionDebugLogger.summarizeEnvironment(environment))")
                completion(environment)
            }
        }

        do {
            try proc.run()
        } catch {
            completion([:])
        }
    }

    func resolvePreferredBackend(completion: @escaping (Backend?, [String: String], String?) -> Void) {
        resolveShellEnvironment { [weak self] environment in
            guard let self else {
                completion(nil, environment, nil)
                return
            }

            let preferredTransport = AppSettings.hasExplicitPreferredTransportChoice
                ? AppSettings.preferredTransport
                : AppSettings.PreferredTransport.automatic
            let preferenceKey = self.backendPreferenceKey(environment: environment)
            SessionDebugLogger.log("backend", "resolving preferred backend. preferredTransport=\(preferredTransport.rawValue)")

            if let selectedBackend = self.selectedBackend,
               self.selectedBackendPreferenceKey == preferenceKey {
                SessionDebugLogger.log("backend", "reusing cached backend selection")
                completion(selectedBackend, environment, nil)
                return
            }

            if preferredTransport != .automatic {
                self.resolveForcedBackend(preferredTransport, environment: environment) { backend, environment, message in
                    if let backend {
                        self.selectedBackend = backend
                        self.selectedBackendPreferenceKey = preferenceKey
                    }
                    completion(backend, environment, message)
                }
                return
            }

            // Auto-select by availability: Claude Code → Codex → direct OpenAI.
            // Orion is single-persona with the bundled starter archive; there
            // is no official-MCP / bearer-token path to negotiate.
            self.resolveClaudeCodeBackend(environment: environment) { claudeBackend in
                if let claudeBackend {
                    SessionDebugLogger.log("backend", "selected Claude backend")
                    self.selectedBackend = claudeBackend
                    self.selectedBackendPreferenceKey = preferenceKey
                    completion(claudeBackend, environment, nil)
                    return
                }

                self.resolveCodexBackend(environment: environment) { codexBackend in
                    if let codexBackend {
                        SessionDebugLogger.log("backend", "selected Codex backend")
                        self.selectedBackend = codexBackend
                        self.selectedBackendPreferenceKey = preferenceKey
                        completion(codexBackend, environment, nil)
                        return
                    }

                    if let key = environment["OPENAI_API_KEY"], !key.isEmpty {
                        SessionDebugLogger.log("backend", "selected direct OpenAI Responses API backend")
                        self.selectedBackend = .openAIResponsesAPI
                        self.selectedBackendPreferenceKey = preferenceKey
                        completion(.openAIResponsesAPI, environment, nil)
                        return
                    }

                    SessionDebugLogger.log("backend", "no backend available")
                    completion(nil, environment, self.backendSetupMessage(environment: environment))
                }
            }
        }
    }

    func backendPreferenceKey(environment: [String: String]) -> String {
        let preferredTransport = AppSettings.hasExplicitPreferredTransportChoice
            ? AppSettings.preferredTransport
            : AppSettings.PreferredTransport.automatic
        return [
            preferredTransport.rawValue,
            AppSettings.preferredClaudeModel.rawValue,
            AppSettings.preferredCodexModel.rawValue,
            AppSettings.preferredOpenAIModel.rawValue,
            (environment["ANTHROPIC_API_KEY"]?.isEmpty == false) ? "anthropic:1" : "anthropic:0",
            (environment["OPENAI_API_KEY"]?.isEmpty == false) ? "openai:1" : "openai:0"
        ].joined(separator: "|")
    }

    func resolveForcedBackend(_ preferredTransport: AppSettings.PreferredTransport, environment: [String: String], completion: @escaping (Backend?, [String: String], String?) -> Void) {
        switch preferredTransport {
        case .automatic:
            completion(nil, environment, nil)
        case .claudeCode:
            resolveClaudeCodeBackend(environment: environment) { backend in
                if let backend {
                    SessionDebugLogger.log("backend", "selected forced Claude backend")
                    completion(backend, environment, nil)
                } else {
                    completion(nil, environment, "Claude Code is selected in Settings, but Claude is not configured. Log into Claude Code or set ANTHROPIC_API_KEY.")
                }
            }
        case .codex:
            resolveCodexBackend(environment: environment) { backend in
                if let backend {
                    SessionDebugLogger.log("backend", "selected forced Codex backend")
                    completion(backend, environment, nil)
                } else {
                    completion(nil, environment, "Codex is selected in Settings, but Codex is not configured. Log into Codex or set OPENAI_API_KEY.")
                }
            }
        case .openAIAPI:
            if let key = environment["OPENAI_API_KEY"], !key.isEmpty {
                SessionDebugLogger.log("backend", "selected forced direct OpenAI Responses API backend")
                completion(.openAIResponsesAPI, environment, nil)
            } else {
                completion(nil, environment, "Direct OpenAI API is selected in Settings, but OPENAI_API_KEY is missing.")
            }
        }
    }

    func resolveClaudeCodeBackend(environment: [String: String], completion: @escaping (Backend?) -> Void) {
        guard let executable = executablePath(named: "claude", environment: environment) else {
            SessionDebugLogger.log("backend", "claude executable not found")
            completion(nil)
            return
        }

        if let apiKey = environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty {
            SessionDebugLogger.log("backend", "claude available via ANTHROPIC_API_KEY")
            completion(.claudeCodeCLI(path: executable))
            return
        }

        runProcess(
            executablePath: executable,
            arguments: ["auth", "status"],
            environment: environment,
            workingDirectory: nil
        ) { status, stdout, _ in
            let isLoggedIn = self.isClaudeAuthenticated(exitCode: status, stdout: stdout)
            SessionDebugLogger.log("backend", "claude auth status exitCode=\(status) authenticated=\(isLoggedIn)")
            completion(isLoggedIn ? .claudeCodeCLI(path: executable) : nil)
        }
    }

    func resolveCodexBackend(environment: [String: String], completion: @escaping (Backend?) -> Void) {
        guard let executable = executablePath(named: "codex", environment: environment) else {
            SessionDebugLogger.log("backend", "codex executable not found")
            completion(nil)
            return
        }

        if let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            SessionDebugLogger.log("backend", "codex available via OPENAI_API_KEY")
            completion(.codexCLI(path: executable))
            return
        }

        runProcess(
            executablePath: executable,
            arguments: ["login", "status"],
            environment: environment,
            workingDirectory: nil
        ) { status, stdout, stderr in
            let isLoggedIn = self.isCodexAuthenticated(exitCode: status, stdout: stdout, stderr: stderr)
            SessionDebugLogger.log("backend", "codex login status exitCode=\(status) authenticated=\(isLoggedIn)")
            completion(isLoggedIn ? .codexCLI(path: executable) : nil)
        }
    }

    func executablePath(named name: String, environment: [String: String]) -> String? {
        let rawPath = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in rawPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func isClaudeAuthenticated(exitCode: Int32, stdout: String) -> Bool {
        if let data = stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let loggedIn = json["loggedIn"] as? Bool {
            return loggedIn
        }
        return exitCode == 0
    }

    func isCodexAuthenticated(exitCode: Int32, stdout: String, stderr: String) -> Bool {
        guard exitCode == 0 else { return false }

        let normalized = "\(stdout)\n\(stderr)".lowercased()
        if normalized.contains("not logged in") || normalized.contains("login required") {
            return false
        }
        if normalized.contains("logged in") || normalized.contains("chatgpt") {
            return true
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func backendStatusMessage(for backend: Backend, environment: [String: String]? = nil) -> String {
        _ = environment
        switch backend {
        case .claudeCodeCLI:
            let modelSuffix = selectedClaudeModel().map { " • model: \($0)" } ?? ""
            return "Using Claude Code CLI\(modelSuffix)"
        case .codexCLI:
            let modelSuffix = selectedCodexModel().map { " • model: \($0)" } ?? ""
            return "Using Codex CLI\(modelSuffix)"
        case .openAIResponsesAPI:
            return "Using direct OpenAI Responses API • model: \(selectedOpenAIModel())"
        }
    }

    func backendSetupMessage(environment: [String: String]) -> String {
        let hasOpenAIKey = !(environment["OPENAI_API_KEY"] ?? "").isEmpty
        let hasAnthropicKey = !(environment["ANTHROPIC_API_KEY"] ?? "").isEmpty

        var lines = [
            "Orion is not connected yet.",
            "",
            "Open Settings to connect one of these:",
            "1. Claude Code",
            "2. Codex / ChatGPT",
            "3. OpenAI API"
        ]

        if hasAnthropicKey || hasOpenAIKey {
            lines.append("")
            lines.append("Detected in your shell:")
            if hasAnthropicKey { lines.append("- `ANTHROPIC_API_KEY`") }
            if hasOpenAIKey { lines.append("- `OPENAI_API_KEY`") }
        }

        return lines.joined(separator: "\n")
    }
}

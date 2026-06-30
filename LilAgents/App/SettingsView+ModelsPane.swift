import AppKit
import SwiftUI

extension SettingsView {
    var modelsPane: some View {
        let _ = detectionRefreshID
        return VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "Models",
                subtitle: "Choose how Orion should answer on this Mac."
            )

            SettingsSectionCard(title: "Behaviour", subtitle: "How Orion shows up on this Mac.") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            AppSettings.applyLaunchAtLoginPreference()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at login")
                                .font(.subheadline.weight(.medium))
                            Text("Open Orion automatically when you log in to your Mac.")
                                .settingsCaption()
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Divider()

                    Toggle(isOn: $useAmbientLLM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI-generated ambient comments")
                                .font(.subheadline.weight(.medium))
                            Text("When idle, Orion makes a one-shot LLM call (via Claude Code) to generate a fresh dry comment every 90–240 seconds. Falls back to a built-in pool if Claude Code isn't installed or the call fails. Off = uses the built-in pool only (no per-bubble cost).")
                                .settingsCaption()
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsSectionCard(title: "Connectors & extensions", subtitle: "Share MCP servers between Claude Desktop and Orion.") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Orion chats through the Claude Code CLI, which uses a separate MCP registry from Claude Desktop. This button copies any MCP servers you've set up in Claude Desktop into Claude Code's config (~/.claude.json) so Orion can use them too. Existing entries are never overwritten — only missing ones are added. A backup is written to ~/.claude.json.orion-backup before any change.")
                        .settingsCaption()

                    HStack(spacing: 12) {
                        Button("Sync MCPs from Claude Desktop") {
                            let result = AppSettings.mirrorClaudeDesktopMCPs()
                            mcpSyncResultMessage = result.summary
                        }
                        .controlSize(.small)

                        if let msg = mcpSyncResultMessage, !msg.isEmpty {
                            Text(msg)
                                .settingsCaption()
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }

            SettingsSectionCard(title: "Runtime", subtitle: modelSectionSubtitle) {
                VStack(alignment: .leading, spacing: 14) {
                    RuntimeSegmentedControl(
                        selection: $preferredTransport,
                        claudeAvailable: $detectedClaudeAvailable,
                        codexAvailable: $detectedCodexAvailable
                    )

                    SettingsInfoRow(
                        icon: selectedRuntimeIcon,
                        iconColor: .accentColor,
                        text: selectedRuntimeDescription
                    )

                    if effectiveModelTransport == .claudeCode {
                        LabeledModelPicker(
                            title: "Claude model",
                            selection: $preferredClaudeModel,
                            options: AppSettings.ClaudeModel.allCases.map { ($0.label, $0.rawValue) }
                        )
                    } else if effectiveModelTransport == .codex {
                        LabeledModelPicker(
                            title: "Codex model",
                            selection: $preferredCodexModel,
                            options: AppSettings.CodexModel.allCases.map { ($0.label, $0.rawValue) }
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledModelPicker(
                                title: "OpenAI model",
                                selection: $preferredOpenAIModel,
                                options: AppSettings.OpenAIModel.allCases.map { ($0.label, $0.rawValue) }
                            )

                            SecureField("Paste OpenAI API key", text: $openAIAPIKey)
                                .textFieldStyle(.roundedBorder)

                            Text("Used only when Orion needs to fall back to the OpenAI API on this Mac.")
                                .settingsCaption()
                        }
                    }
                }
            }
        }
    }

    var aboutPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "About",
                subtitle: "Credits, project story, and links to learn more."
            )

            SettingsSectionCard(title: "Version", subtitle: "Which release of Orion you're running.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Orion")
                            .font(.subheadline.weight(.medium))
                        Text(Self.formattedAppVersion())
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Sparkle checks for updates automatically every 24 hours. You can also click 'Check for Updates…' from the menu bar icon.")
                        .settingsCaption()
                    Link("All releases on GitHub", destination: URL(string: "https://github.com/justinwilliames/orion-by-orbit/releases")!)
                        .font(.subheadline.weight(.medium))
                }
            }

            SettingsSectionCard(title: "Credits", subtitle: "Original projects this builds on.") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Orion is built on top of the original lil agents project by Ryan Stephen, and the Lil-Lenny fork by Ben Shih.")
                        .settingsCaption()

                    Link("Ryan Stephen · Original lil agents project", destination: URL(string: "https://github.com/ryanstephen/lil-agents")!)
                        .font(.subheadline.weight(.medium))

                    Link("Ben Shih · Lil-Lenny fork", destination: URL(string: "https://github.com/hbshih/lenny-lil-agents")!)
                        .font(.subheadline.weight(.medium))
                }
            }

            SettingsSectionCard(title: "About Orion", subtitle: "Orbit's menu-bar lifecycle assistant.") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Orion is Orbit's menu-bar lifecycle assistant — same Orbit voice, narrower surface than the full MCP extension. Ask about lifecycle marketing, deliverability, Braze, retention economics — anything from the Orbit playbook.")
                        .settingsCaption()

                    Link("Orbit · The hub for lifecycle marketing & AI workflows", destination: URL(string: "https://yourorbit.team")!)
                        .font(.subheadline.weight(.medium))

                    Text("This is a personality layer on whichever provider you connect in Settings — not an archive, not RAG. For deeper grounding in the full Orbit guide library, install the Orbit MCP for Claude Desktop.")
                        .settingsCaption()

                    Link("Install Orbit (.mcpb · free for everyone)", destination: URL(string: "https://yourorbit.team/download")!)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    /// Human-readable build label.
    /// Format: `v0.1.63 (build 142)` when both fields are present;
    /// gracefully degrades when one is missing.
    static func formattedAppVersion() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? ""
        let build = (info["CFBundleVersion"] as? String) ?? ""
        let cleanedShort = short.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBuild = build.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanedShort.isEmpty && !cleanedBuild.isEmpty {
            return "v\(cleanedShort) (build \(cleanedBuild))"
        }
        if !cleanedShort.isEmpty {
            return "v\(cleanedShort)"
        }
        if !cleanedBuild.isEmpty {
            return "build \(cleanedBuild)"
        }
        return "version unknown"
    }

    var developerPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "Developer",
                subtitle: "Behavior toggles and preview states for local testing."
            )

            SettingsSectionCard(title: "Developer", subtitle: "Logs and preview behavior.") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show detailed session logs in Xcode", isOn: $debugLoggingEnabled)
                        Text("Sensitive tokens stay redacted in logs.")
                            .settingsCaption()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Welcome preview")
                            .font(.headline)

                        Picker("Preview mode", selection: $welcomePreviewMode) {
                            ForEach(AppSettings.WelcomePreviewMode.allCases, id: \.rawValue) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reset")
                            .font(.headline)

                        Text("Clear Orion's local settings and remove its Claude/Codex archive MCP configuration so you can test the setup flow from a clean state.")
                            .settingsCaption()

                        Button("Reset all local data…", role: .destructive) {
                            showResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - Model/transport helpers

    var effectiveModelTransport: AppSettings.PreferredTransport {
        if !AppSettings.hasExplicitPreferredTransportChoice {
            if detectedClaudeAvailable == true { return .claudeCode }
            if detectedCodexAvailable == true  { return .codex }
            return .openAIAPI
        }

        if let selected = AppSettings.PreferredTransport(rawValue: preferredTransport), selected != .automatic {
            return selected
        }
        // Use async-detected results — never call detection synchronously on the main thread
        if detectedClaudeAvailable == true { return .claudeCode }
        if detectedCodexAvailable == true  { return .codex }
        return .openAIAPI
    }

    var modelSectionSubtitle: String {
        switch effectiveModelTransport {
        case .claudeCode: return "Orion will answer through Claude Code."
        case .codex:      return "Orion will answer through Codex."
        case .openAIAPI:  return "Orion will answer through the OpenAI API."
        case .automatic:  return "Detecting available runtimes…"
        }
    }

    var selectedRuntimeDescription: String {
        switch effectiveModelTransport {
        case .claudeCode: return "Choose which Claude model Orion should use."
        case .codex:      return "Choose which Codex model Orion should use."
        case .openAIAPI:  return "Choose which OpenAI model Orion should use and add an API key below."
        case .automatic:  return "Detecting available runtimes…"
        }
    }

    var selectedRuntimeIcon: String {
        switch effectiveModelTransport {
        case .claudeCode: return "person.crop.square.fill"
        case .codex:      return "terminal.fill"
        case .openAIAPI:  return "network.badge.shield.half.filled"
        case .automatic:  return "arrow.triangle.branch"
        }
    }
}

// MARK: - Custom segmented runtime control

private struct RuntimeSegment {
    let label: String
    let tag: String
    /// nil = still detecting, true/false = result known
    let available: Bool?
}

struct RuntimeSegmentedControl: View {
    @Binding var selection: String
    @Binding var claudeAvailable: Bool?
    @Binding var codexAvailable: Bool?

    private var segments: [RuntimeSegment] {
        [
            RuntimeSegment(label: "Claude Code", tag: AppSettings.PreferredTransport.claudeCode.rawValue, available: claudeAvailable),
            RuntimeSegment(label: "Codex",       tag: AppSettings.PreferredTransport.codex.rawValue,      available: codexAvailable),
            RuntimeSegment(label: "OpenAI API",  tag: AppSettings.PreferredTransport.openAIAPI.rawValue,  available: true),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.tag) { segment in
                segmentButton(segment)
                    .overlay(alignment: .trailing) {
                        if segment.tag != segments.last?.tag {
                            Rectangle()
                                .fill(Color(NSColor.separatorColor).opacity(0.6))
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        .task {
            async let claude = Task.detached(priority: .userInitiated) { AppSettings.hasDetectedClaudeLogin }.value
            async let codex  = Task.detached(priority: .userInitiated) { AppSettings.hasDetectedCodexLogin  }.value
            let (c, d) = await (claude, codex)
            claudeAvailable = c
            codexAvailable  = d

            // Keep auto-resolving the best runtime until the user explicitly picks one.
            if !AppSettings.hasExplicitPreferredTransportChoice {
                if c {
                    selection = AppSettings.PreferredTransport.claudeCode.rawValue
                } else if d {
                    selection = AppSettings.PreferredTransport.codex.rawValue
                } else {
                    selection = AppSettings.PreferredTransport.openAIAPI.rawValue
                }
            }
        }
    }

    @ViewBuilder
    private func segmentButton(_ segment: RuntimeSegment) -> some View {
        let isSelected   = selection == segment.tag
        let isDetecting  = segment.available == nil
        let isAvailable  = segment.available == true

        Button {
            AppSettings.hasExplicitPreferredTransportChoice = true
            selection = segment.tag
        } label: {
            VStack(spacing: 2) {
                Text(segment.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(labelColor(isSelected: isSelected, isAvailable: isAvailable, isDetecting: isDetecting))

                if isDetecting {
                    // Placeholder to keep row height stable while checking
                    Text("Checking…")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                } else if !isAvailable {
                    Text("Not installed")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected && isAvailable {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.18))
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable && !isDetecting)
    }

    private func labelColor(isSelected: Bool, isAvailable: Bool, isDetecting: Bool) -> Color {
        if isDetecting   { return Color(NSColor.secondaryLabelColor) }
        if !isAvailable  { return Color(NSColor.tertiaryLabelColor) }
        if isSelected    { return Color.accentColor }
        return Color(NSColor.labelColor)
    }
}

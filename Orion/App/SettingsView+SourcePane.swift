import AppKit
import SwiftUI

extension SettingsView {
    var sourcePane: some View {
        let _ = detectionRefreshID
        return VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "Answer source",
                subtitle: "Choose whether Orion answers from the local archive or the full archive MCP."
            )

            SettingsSectionCard(title: "Answer source", subtitle: "Local archive is fast. Remote archive MCP is broader.") {
                VStack(spacing: 0) {
                    sourceRow(
                        mode: .starterPack,
                        title: "Starter Pack",
                        subtitle: "Bundled on this Mac",
                        detail: "Fast, local, and ready immediately for quick questions and demos.",
                        isLast: false
                    )

                    sourceRow(
                        mode: .officialMCP,
                        title: "Full archive",
                        subtitle: "Official archive access",
                        detail: "Broader and deeper answers from the remote archive.",
                        isLast: archiveAccessMode != AppSettings.ArchiveAccessMode.officialMCP.rawValue
                    )
                }

                if AppSettings.effectiveArchiveAccessMode == .officialMCP || archiveAccessMode == AppSettings.ArchiveAccessMode.officialMCP.rawValue {
                    Divider()
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        // Reconnect warning — shown when a previous auth failure was detected
                        if mcpReconnectNeeded {
                            SettingsInfoRow(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .orange,
                                text: "The archive connection failed. Your auth token may have expired — enter a new one below to reconnect."
                            )
                        }

                        if AppSettings.officialLennyMCPToken != nil {
                            SettingsInfoRow(
                                icon: "checkmark.circle.fill",
                                iconColor: .accentColor,
                                text: "Your auth key is saved on this Mac. Orion will use it automatically when you send a message."
                            )
                        } else {
                            // Show a hint when native CLI config is detected but no Settings token
                            let nativeSources = AppSettings.detectedOfficialMCPSources
                            if nativeSources.contains(.claudeGlobalConfig) || nativeSources.contains(.codexGlobalConfig) {
                                SettingsInfoRow(
                                    icon: "info.circle.fill",
                                    iconColor: Color.secondary,
                                    text: "Archive MCP URL detected in your CLI config. Enter an auth key below to activate authentication."
                                )
                            }

                            HStack(alignment: .center, spacing: 12) {
                                SecureField("Paste auth key", text: $officialToken)
                                    .textFieldStyle(.roundedBorder)

                                Button("Save and connect") {
                                    saveOfficialArchiveToken()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Open archive site") {
                                    NSWorkspace.shared.open(officialArchiveURL)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text("Orion stores this auth key locally on this Mac and, when you save it here, configures any detected Codex or Claude Code install for the official archive too.")
                                .settingsCaption()
                        }

                        if let sourcePaneStatusMessage, !sourcePaneStatusMessage.isEmpty {
                            SettingsInfoRow(
                                icon: "checkmark.circle.fill",
                                iconColor: .accentColor,
                                text: sourcePaneStatusMessage
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func sourceRow(
        mode: AppSettings.ArchiveAccessMode,
        title: String,
        subtitle: String,
        detail: String,
        isLast: Bool
    ) -> some View {
        // Use the effective mode for the selected indicator so native CLI
        // detection is reflected, not just the stored preference.
        let effectiveMode = AppSettings.effectiveArchiveAccessMode
        let selected = effectiveMode.rawValue == mode.rawValue

        Button {
            archiveAccessMode = mode.rawValue
            AppSettings.hasExplicitStarterPackChoice = (mode == .starterPack)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if selected {
                            SettingsStatusPill(title: "Selected", systemImage: "checkmark.circle.fill", tone: .accent)
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(detail)
                        .settingsCaption()
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.06) : Color.clear)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Divider()
                        .padding(.leading, 46)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func saveOfficialArchiveToken() {
        let trimmed = officialToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sourcePaneErrorMessage = "Paste the auth key first."
            return
        }

        do {
            let result = try OfficialMCPInstaller.install(token: trimmed)
            officialToken = trimmed

            if result.storedTokenOnly {
                sourcePaneStatusMessage = "Saved locally. Orion will use it automatically, and detected CLI tools can be configured later."
            } else {
                let updated = result.updatedTargets.map(\.label)
                let preserved = result.preservedTargets.map(\.label)
                let updatedText = updated.isEmpty ? nil : sourcePaneNaturalList(updated)
                let preservedText = preserved.isEmpty ? nil : sourcePaneNaturalList(preserved)

                if let updatedText, let preservedText {
                    sourcePaneStatusMessage = "Saved locally. Configured \(updatedText) and kept the existing setup in \(preservedText)."
                } else if let updatedText {
                    sourcePaneStatusMessage = "Saved locally and configured \(updatedText)."
                } else if let preservedText {
                    sourcePaneStatusMessage = "Saved locally. Existing setup in \(preservedText) was kept."
                } else {
                    sourcePaneStatusMessage = "Saved locally and connected."
                }
            }

            sourcePaneErrorMessage = nil
            refreshDetectionStateAndDefaults()
        } catch {
            sourcePaneErrorMessage = error.localizedDescription
        }
    }

    private func sourcePaneNaturalList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            return "\(items.dropLast().joined(separator: ", ")), and \(items.last ?? "")"
        }
    }
}

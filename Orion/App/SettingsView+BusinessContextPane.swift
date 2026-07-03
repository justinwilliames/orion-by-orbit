import AppKit
import SwiftUI

extension SettingsView {
    var businessContextPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "Business context",
                subtitle: "Helps me skip beginner framing and reach for ESP-specific examples. Stays on your Mac. No customer data."
            )

            BusinessContextEditor(
                initial: AppSettings.businessContext ?? .empty(),
                hasExistingContext: AppSettings.businessContext != nil,
                onSave: { ctx in
                    AppSettings.businessContext = ctx
                    AppSettings.markBusinessContextPromptShown()
                    NotificationCenter.default.post(name: .liLJustinBusinessContextDidChange, object: nil)
                },
                onClear: {
                    AppSettings.businessContext = nil
                    NotificationCenter.default.post(name: .liLJustinBusinessContextDidChange, object: nil)
                }
            )
        }
    }
}

/// Form for capturing/editing `BusinessContext`. Reused by the
/// Settings pane. Each picker maps to a curated option list with
/// "Other (specify)" as the final row that swaps in a free text field.
struct BusinessContextEditor: View {
    let initial: BusinessContext
    let hasExistingContext: Bool
    let onSave: (BusinessContext) -> Void
    let onClear: () -> Void

    @State private var verticalChoice: String = ""
    @State private var verticalCustom: String = ""
    @State private var espChoice: String = ""
    @State private var espCustom: String = ""
    @State private var channel: String = ""
    @State private var listSize: String = ""
    @State private var teamSize: String = ""
    @State private var pain: String = ""
    @State private var savedNoticeVisible: Bool = false

    /// Sentinel that flags the picker selection as "Other → free text".
    /// Stored value is whatever the user types into the custom field.
    private static let otherSentinel = "__other__"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionCard(title: "Your program", subtitle: "Five quick picks plus an optional note. Edit any time.") {
                VStack(alignment: .leading, spacing: 18) {
                    verticalRow
                    Divider()
                    espRow
                    Divider()
                    radioRow(
                        title: "Primary channel",
                        options: BusinessContextOptions.channels,
                        selection: $channel
                    )
                    Divider()
                    radioRow(
                        title: "List size",
                        options: BusinessContextOptions.listSizeBands,
                        selection: $listSize
                    )
                    Divider()
                    radioRow(
                        title: "Team size",
                        options: BusinessContextOptions.teamSizes,
                        selection: $teamSize
                    )
                    Divider()
                    painRow
                }
            }

            HStack(spacing: 12) {
                Button(hasExistingContext ? "Save changes" : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!resolvedContext().isComplete)

                if savedNoticeVisible {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }

                Spacer()

                if hasExistingContext {
                    Button("Clear") {
                        onClear()
                        loadFromInitial(.empty())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .onAppear { loadFromInitial(initial) }
    }

    // MARK: - Rows

    @ViewBuilder
    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vertical")
                .font(.subheadline.weight(.medium))

            Picker("Vertical", selection: $verticalChoice) {
                ForEach(BusinessContextOptions.verticals, id: \.self) { option in
                    Text(option).tag(option)
                }
                Text("Other (specify)").tag(Self.otherSentinel)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if verticalChoice == Self.otherSentinel {
                TextField("e.g. Pet care SaaS", text: $verticalCustom)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private var espRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ESP / CRM tool")
                .font(.subheadline.weight(.medium))

            Picker("ESP / CRM tool", selection: $espChoice) {
                ForEach(BusinessContextOptions.espTools, id: \.self) { option in
                    Text(option).tag(option)
                }
                Text("Other (specify)").tag(Self.otherSentinel)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if espChoice == Self.otherSentinel {
                TextField("e.g. Bloomreach Engagement", text: $espCustom)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private func radioRow(title: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .horizontalRadioLayout()
        }
    }

    @ViewBuilder
    private var painRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Biggest current focus or pain")
                    .font(.subheadline.weight(.medium))
                Text("(optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pain.count)/\(BusinessContext.painCharacterLimit)")
                    .font(.caption)
                    .foregroundStyle(pain.count > BusinessContext.painCharacterLimit ? Color.orange : .secondary)
                    .monospacedDigit()
            }

            TextField("e.g. Reactivation flow underperforming, Apple MPP killing open-rate signal", text: $pain, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onChange(of: pain) { _, newValue in
                    if newValue.count > BusinessContext.painCharacterLimit {
                        pain = String(newValue.prefix(BusinessContext.painCharacterLimit))
                    }
                }

            Text("General description only — don't paste customer data, internal segment IDs, or anything you wouldn't share with a peer at a meet-up.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State helpers

    private func loadFromInitial(_ ctx: BusinessContext) {
        // Map stored vertical/ESP back into picker-or-custom state.
        if BusinessContextOptions.verticals.contains(ctx.vertical) {
            verticalChoice = ctx.vertical
            verticalCustom = ""
        } else if !ctx.vertical.isEmpty {
            verticalChoice = Self.otherSentinel
            verticalCustom = ctx.vertical
        } else {
            verticalChoice = ""
            verticalCustom = ""
        }

        if BusinessContextOptions.espTools.contains(ctx.espTool) {
            espChoice = ctx.espTool
            espCustom = ""
        } else if !ctx.espTool.isEmpty {
            espChoice = Self.otherSentinel
            espCustom = ctx.espTool
        } else {
            espChoice = ""
            espCustom = ""
        }

        channel = ctx.primaryChannel
        listSize = ctx.listSizeBand
        teamSize = ctx.teamSize
        pain = ctx.biggestPain
        savedNoticeVisible = false
    }

    private func resolvedContext() -> BusinessContext {
        let resolvedVertical = verticalChoice == Self.otherSentinel
            ? verticalCustom.trimmingCharacters(in: .whitespacesAndNewlines)
            : verticalChoice
        let resolvedESP = espChoice == Self.otherSentinel
            ? espCustom.trimmingCharacters(in: .whitespacesAndNewlines)
            : espChoice

        return BusinessContext(
            vertical: resolvedVertical,
            espTool: resolvedESP,
            primaryChannel: channel,
            listSizeBand: listSize,
            teamSize: teamSize,
            biggestPain: pain.trimmingCharacters(in: .whitespacesAndNewlines),
            schemaVersion: BusinessContext.currentSchemaVersion,
            capturedAt: Date()
        )
    }

    private func save() {
        let ctx = resolvedContext()
        guard ctx.isComplete else { return }
        onSave(ctx)
        withAnimation(.easeOut(duration: 0.2)) {
            savedNoticeVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                savedNoticeVisible = false
            }
        }
    }
}

private extension View {
    /// Inline radio group reads more naturally for short option lists
    /// than a vertical column. SwiftUI's radio picker stacks vertically
    /// by default — wrap in a horizontal frame to coax it sideways
    /// where there's room.
    @ViewBuilder
    func horizontalRadioLayout() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
    }
}

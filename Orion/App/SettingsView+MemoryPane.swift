import AppKit
import SwiftUI

extension SettingsView {
    var memoryPane: some View {
        MemoryPaneRoot()
    }
}

/// Settings → Memory pane.
///
/// Lists every fact Orion has remembered. Sir can pin (always
/// included in system prompt), edit body, delete a single entry, or
/// clear them all. Two top-level toggles — auto-extract and
/// conversation-history persistence — sit above the list so the
/// behaviour can be turned off if either feels noisy.
private struct MemoryPaneRoot: View {
    @AppStorage(AppSettings.autoExtractMemoryKey) private var autoExtractEnabled: Bool = true

    @State private var entries: [MemoryEntry] = []
    @State private var editingEntry: MemoryEntry?
    @State private var showClearAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeader(
                title: "Memory",
                subtitle: "Durable facts Orion remembers about you between conversations. Stored on your Mac. Never includes specific names, emails, phone numbers, exact financials, or anything that looks like a secret. Conversation transcripts are deliberately not stored — chats are fleeting by design."
            )

            SettingsSectionCard(title: "Behaviour", subtitle: "How Orion uses memory.") {
                Toggle(isOn: $autoExtractEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-remember durable facts")
                            .font(.subheadline.weight(.medium))
                        Text("After each substantive answer, run a one-shot extraction call on the connected provider to identify 0–2 facts worth saving. PII filter and prompt-side guidance keep sensitive specifics out. Off = Orion never adds memories on its own; you can still capture them manually with phrases like 'remember that…'")
                            .settingsCaption()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            SettingsSectionCard(
                title: "Remembered facts",
                subtitle: entries.isEmpty
                    ? "Nothing yet. Have a chat — durable facts will appear here automatically."
                    : "\(entries.count) entr\(entries.count == 1 ? "y" : "ies"). Pin the ones that should always be in context. Star (★) marks pinned."
            ) {
                if entries.isEmpty {
                    Text("Tip: in chat you can also say things like \"remember that I'm migrating from Mailchimp\" to capture facts directly. Sensitive specifics (names, emails, exact figures) are never stored.")
                        .settingsCaption()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            MemoryRow(
                                entry: entry,
                                onTogglePin: { togglePin(entry) },
                                onEdit: { editingEntry = entry },
                                onDelete: { delete(entry) }
                            )
                            if entry.id != entries.last?.id {
                                Divider().padding(.vertical, 6)
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Clear all memory…", role: .destructive) {
                            showClearAllConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: MemoryStore.didChangeNotification)) { _ in
            reload()
        }
        .alert("Clear all memory?", isPresented: $showClearAllConfirmation) {
            Button("Clear all", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every remembered fact. Conversations and your business context aren't affected. There's no undo.")
        }
        .sheet(item: $editingEntry) { entry in
            MemoryEditSheet(entry: entry) { updated in
                if let updated {
                    MemoryStore.save(updated, bypassSensitivityFilter: true)
                }
                editingEntry = nil
            }
        }
    }

    private func reload() {
        entries = MemoryStore.all()
    }

    private func togglePin(_ entry: MemoryEntry) {
        var updated = entry
        updated.pinned.toggle()
        MemoryStore.save(updated, bypassSensitivityFilter: true)
    }

    private func delete(_ entry: MemoryEntry) {
        MemoryStore.delete(entry.id)
    }

    private func clearAll() {
        MemoryStore.clearAll()
    }
}

private struct MemoryRow: View {
    let entry: MemoryEntry
    let onTogglePin: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTogglePin) {
                Image(systemName: entry.pinned ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(entry.pinned ? Color.yellow : Color.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(entry.pinned ? "Pinned — always in context" : "Pin to keep this fact in every system prompt")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                    Text(entry.kind.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                    Spacer()
                    Text(entry.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(entry.body)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.description.isEmpty, entry.description != entry.body {
                    Text(entry.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

private struct MemoryEditSheet: View {
    let entry: MemoryEntry
    let onClose: (MemoryEntry?) -> Void

    @State private var name: String
    @State private var descriptionText: String
    @State private var bodyText: String
    @State private var kind: MemoryEntry.Kind

    init(entry: MemoryEntry, onClose: @escaping (MemoryEntry?) -> Void) {
        self.entry = entry
        self.onClose = onClose
        _name = State(initialValue: entry.name)
        _descriptionText = State(initialValue: entry.description)
        _bodyText = State(initialValue: entry.body)
        _kind = State(initialValue: entry.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit memory")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.caption.weight(.medium))
                TextField("Title", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type").font(.caption.weight(.medium))
                Picker("Type", selection: $kind) {
                    ForEach(MemoryEntry.Kind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Body — the durable fact").font(.caption.weight(.medium))
                TextField("Body", text: $bodyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description — short hook for the list").font(.caption.weight(.medium))
                TextField("Description", text: $descriptionText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { onClose(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var updated = entry
                    updated.name = name
                    updated.description = descriptionText
                    updated.body = bodyText
                    updated.kind = kind
                    onClose(updated)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

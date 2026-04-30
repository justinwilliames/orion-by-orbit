import AppKit
import Foundation
import SwiftUI

// Notes browser — a small two-pane window for viewing, editing, and
// deleting the daily YYYY-MM-DD.md files appended by Quick Note. Lives
// at `~/Orbit/notes/`. Reachable via the "View past notes" right-click
// menu item on Orion.
//
// SwiftUI for the layout (less AppKit boilerplate), wrapped in an
// NSPanel so it floats independently of the main app windows.

// MARK: - Store

/// Reads + writes the notes directory. Re-scans on every save / delete
/// so the day list stays in sync without a file-watch dependency. The
/// folder count is small (one file per day), the rescans are cheap.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var days: [String] = []

    private var dir: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Orbit")
            .appendingPathComponent("notes")
    }

    init() {
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        days = urls
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            // Sorted descending — most-recent day at the top of the list.
            .sorted(by: >)
    }

    func read(day: String) -> String {
        let file = dir.appendingPathComponent("\(day).md")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    func save(day: String, content: String) {
        let file = dir.appendingPathComponent("\(day).md")
        try? content.write(to: file, atomically: true, encoding: .utf8)
        refresh()
    }

    func delete(day: String) {
        let file = dir.appendingPathComponent("\(day).md")
        try? FileManager.default.removeItem(at: file)
        refresh()
    }
}


// MARK: - View

struct NotesBrowserView: View {
    @StateObject private var store = NotesStore()
    @State private var selectedDay: String?
    @State private var draft: String = ""
    @State private var dirty: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)

            editor
                .frame(minWidth: 420)
        }
        .frame(minWidth: 700, minHeight: 460)
        .onChange(of: selectedDay) { _, newValue in
            loadDraft(for: newValue)
        }
        .onAppear {
            // Seed selection with the most recent day if any exist.
            if selectedDay == nil, let first = store.days.first {
                selectedDay = first
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload from disk")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if store.days.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No notes yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Right-click Orion → Quick note…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedDay) {
                    ForEach(store.days, id: \.self) { day in
                        Text(day)
                            .font(.system(.body, design: .monospaced))
                            .tag(day)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let day = selectedDay {
                HStack {
                    Text(day)
                        .font(.system(.headline, design: .monospaced))
                    if dirty {
                        Text("• unsaved")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Save") {
                        store.save(day: day, content: draft)
                        dirty = false
                    }
                    .keyboardShortcut("s")
                    .disabled(!dirty)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this day's notes")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                TextEditor(text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .onChange(of: draft) { _, _ in
                        dirty = true
                    }
            } else {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Select a day from the sidebar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "Delete this day's notes?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let day = selectedDay {
                    store.delete(day: day)
                    selectedDay = store.days.first
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let day = selectedDay {
                Text("\(day).md will be removed permanently.")
            }
        }
    }

    private func loadDraft(for day: String?) {
        if let day {
            draft = store.read(day: day)
        } else {
            draft = ""
        }
        dirty = false
    }
}


// MARK: - Window controller

/// Singleton owner of the floating browser window. Reuses the same
/// NSPanel across menu invocations so the user's split-pane sizing
/// and selection persist within a session.
@MainActor
final class NotesBrowserController: NSObject, NSWindowDelegate {
    static let shared = NotesBrowserController()

    private var window: NSPanel?

    private override init() { super.init() }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Orion · Notes"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: NotesBrowserView())

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 380
            let y = frame.midY - 250
            panel.setFrame(NSRect(x: x, y: y, width: 760, height: 500), display: true)
        }

        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}

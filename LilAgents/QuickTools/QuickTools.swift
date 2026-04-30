import AppKit
import Foundation
import SwiftUI

// Quick productivity tools surfaced from Orion's right-click menu.
// Designed to be light-touch — none of these grab focus or fire popups
// unless the user explicitly invokes them. Each tool is self-contained
// and has no dependency outside this file.

// MARK: - Pomodoro

/// 25/5 focus + break cycle. State changes are surfaced through the
/// existing character bubble system: a short status bubble at the start
/// of each phase, the per-turn completion bubble + sound at phase end.
/// Mid-phase, the remaining time is exposed via the character's hover
/// tooltip — quiet but on-demand.
final class PomodoroController {
    static let shared = PomodoroController()

    enum Phase {
        case idle
        case focus
        case shortBreak
        case longBreak
    }

    static let focusDuration: TimeInterval = 25 * 60
    static let shortBreakDuration: TimeInterval = 5 * 60
    static let longBreakDuration: TimeInterval = 20 * 60
    /// Classical Pomodoro: every Nth focus phase ends with a long break
    /// instead of a short one. Four cycles per group is the textbook
    /// number — long enough to feel earned, short enough that the long
    /// break arrives within a couple of hours of starting.
    static let focusesPerLongBreak: Int = 4

    private(set) var phase: Phase = .idle
    private(set) var phaseEndsAt: Date?
    /// Tracks completed focus phases within the current group of N. Reset
    /// when the long break fires (start of next group) and when the user
    /// manually stops the timer.
    private(set) var completedFocusCycles: Int = 0
    private var timer: Timer?

    /// Wired by LilAgentsController so the Pomodoro can drive Orion's
    /// status bubble without depending on the character type directly.
    /// `onTickRefresh` fires every second with the current label
    /// ("Focus 14:32" / "Break 4:51") plus the phase, so the caller
    /// can colour the bubble (red for focus, green for break) and
    /// hide it on idle. `onPhaseEnd` fires once per phase boundary
    /// for the completion bubble + chime.
    var onTickRefresh: ((_ text: String, _ phase: Phase) -> Void)?
    var onPhaseEnd: ((Phase, _ completionText: String) -> Void)?

    private init() {}

    var isRunning: Bool { phase != .idle }

    func toggle() {
        if isRunning { stop() } else { startFocus() }
    }

    func startFocus() {
        beginPhase(.focus, duration: Self.focusDuration)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        phaseEndsAt = nil
        completedFocusCycles = 0
        onTickRefresh?("", .idle)
    }

    private func beginPhase(_ newPhase: Phase, duration: TimeInterval) {
        timer?.invalidate()
        phase = newPhase
        phaseEndsAt = Date().addingTimeInterval(duration)
        // Push the initial countdown text immediately so the bubble
        // appears on the same runloop tick that the menu action returns.
        emitTick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let phaseEndsAt else { return }
        let remaining = phaseEndsAt.timeIntervalSinceNow
        if remaining <= 0 {
            finishCurrentPhase()
        } else {
            emitTick()
        }
    }

    private func finishCurrentPhase() {
        timer?.invalidate()
        timer = nil
        let just = phase
        switch just {
        case .focus:
            completedFocusCycles += 1
            if completedFocusCycles >= Self.focusesPerLongBreak {
                // End of a 4-cycle group → long break, then reset the
                // counter so the next group starts fresh.
                completedFocusCycles = 0
                onPhaseEnd?(just, "Focus done — long break (you've earned it)")
                beginPhase(.longBreak, duration: Self.longBreakDuration)
            } else {
                onPhaseEnd?(just, "Focus done — 5 min break (\(completedFocusCycles)/\(Self.focusesPerLongBreak))")
                beginPhase(.shortBreak, duration: Self.shortBreakDuration)
            }
        case .shortBreak:
            // Auto-loop into the next focus phase. The user manually
            // stops the Pomodoro by clicking the menu item again.
            onPhaseEnd?(just, "Break done — back to focus")
            beginPhase(.focus, duration: Self.focusDuration)
        case .longBreak:
            onPhaseEnd?(just, "Long break done — back to focus")
            beginPhase(.focus, duration: Self.focusDuration)
        case .idle:
            break
        }
    }

    private func emitTick() {
        guard let phaseEndsAt else { onTickRefresh?("", .idle); return }
        let remaining = max(0, phaseEndsAt.timeIntervalSinceNow)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        let label: String
        switch phase {
        case .focus:      label = "Focus"
        case .shortBreak: label = "Break"
        case .longBreak:  label = "Long break"
        case .idle:       label = ""
        }
        onTickRefresh?(String(format: "%@ %d:%02d", label, mins, secs), phase)
    }

    /// Menu item title — lets the right-click menu read the live state
    /// without leaking the Phase enum to AppKit code. While focusing,
    /// surfaces the position in the 4-cycle group so the user knows
    /// how close the long break is.
    var menuTitle: String {
        switch phase {
        case .idle:
            return "Start Pomodoro"
        case .focus:
            // completedFocusCycles increments at the *end* of each focus
            // phase, so during the current focus it's still "n/4" where
            // n is the upcoming completion count.
            return "Stop Pomodoro (focus \(completedFocusCycles + 1)/\(Self.focusesPerLongBreak))"
        case .shortBreak:
            return "Stop Pomodoro (on break)"
        case .longBreak:
            return "Stop Pomodoro (long break)"
        }
    }
}


// MARK: - Quick Note

/// SwiftUI capture view for the floating Quick Note panel. Multi-line
/// TextEditor — Return inserts a newline as expected; saving is the
/// explicit Save button (or ⌘↩). Esc cancels without writing.
private struct QuickNoteCaptureView: View {
    @State private var text: String = ""
    @FocusState private var editorFocused: Bool

    var onSave: (String) -> Void
    var onCancel: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .focused($editorFocused)

                if text.isEmpty {
                    Text("What's the note? Multi-line is fine. ⌘↩ to save, Esc to cancel.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 120)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 480, minHeight: 200)
        .onAppear { editorFocused = true }
    }
}

/// Floating panel host for the Quick Note capture view. Saves entries
/// to `~/Orbit/notes/YYYY-MM-DD.md`, one timestamped line per entry,
/// so a day's notes accumulate in a single file rather than
/// fragmenting the workspace.
final class QuickNoteController: NSObject, NSWindowDelegate {
    static let shared = QuickNoteController()

    private var panel: NSPanel?

    private override init() { super.init() }

    func show() {
        if let existing = panel {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick note"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickNoteCaptureView(
            onSave: { [weak self] text in self?.commit(text) },
            onCancel: { [weak self] in self?.close() }
        ))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 260
            let y = frame.midY + 30
            panel.setFrame(NSRect(x: x, y: y, width: 520, height: 220), display: true)
        }

        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func commit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { close(); return }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Orbit").appendingPathComponent("notes")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let day = ISO8601DateFormatter.dayFormatter.string(from: Date())
        let file = dir.appendingPathComponent("\(day).md")
        let stamp = ISO8601DateFormatter.timeFormatter.string(from: Date())
        // Multi-line notes are indented under the bullet so the
        // ~/Orbit/notes/YYYY-MM-DD.md file stays a clean Markdown
        // bulleted list when read back.
        let body = text
            .components(separatedBy: "\n")
            .enumerated()
            .map { idx, line in idx == 0 ? line : "  \(line)" }
            .joined(separator: "\n")
        let entry = "- \(stamp) — \(body)\n"

        if let data = entry.data(using: .utf8) {
            if fm.fileExists(atPath: file.path),
               let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                let header = "# Notes — \(day)\n\n".data(using: .utf8) ?? Data()
                try? (header + data).write(to: file)
            }
        }
        close()
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel = nil
        return true
    }
}

private extension ISO8601DateFormatter {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}


// MARK: - Clipboard counter

/// Reads the current clipboard text and surfaces character/word counts
/// via a transient NSAlert. Useful for subject lines / push copy where
/// length matters more than nuance.
enum ClipboardCounter {
    static func showCount() {
        let pb = NSPasteboard.general
        let text = pb.string(forType: .string) ?? ""
        let chars = text.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        let alert = NSAlert()
        alert.messageText = chars == 0 ? "Clipboard is empty" : "Clipboard"
        alert.informativeText = chars == 0
            ? "Nothing to count."
            : "\(chars) character\(chars == 1 ? "" : "s")  ·  \(words) word\(words == 1 ? "" : "s")"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}


// MARK: - Open ~/Orbit folder

/// Reveals the local Orbit workspace in Finder. Creates the folder if
/// it doesn't yet exist so the menu item never silently no-ops. The
/// `revealNotes` variant scopes to the notes subdirectory — used by the
/// "View past notes" menu item so the user lands directly where the
/// daily .md files live instead of having to drill in.
enum OpenOrbitFolder {
    static func reveal() {
        revealDirectory(named: nil)
    }

    static func revealNotes() {
        revealDirectory(named: "notes")
    }

    private static func revealDirectory(named: String?) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var dir = home.appendingPathComponent("Orbit")
        if let named { dir.appendPathComponent(named) }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

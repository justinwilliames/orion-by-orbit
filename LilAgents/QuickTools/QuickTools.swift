import AppKit
import Foundation

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
@MainActor
final class PomodoroController {
    static let shared = PomodoroController()

    enum Phase {
        case idle
        case focus
        case shortBreak
    }

    static let focusDuration: TimeInterval = 25 * 60
    static let shortBreakDuration: TimeInterval = 5 * 60

    private(set) var phase: Phase = .idle
    private(set) var phaseEndsAt: Date?
    private var timer: Timer?

    /// Set by LilAgentsController so the Pomodoro can drive bubbles +
    /// tooltips on the character without depending on the character
    /// type directly.
    var onPhaseStart: ((Phase, _ statusText: String) -> Void)?
    var onPhaseEnd: ((Phase, _ completionText: String) -> Void)?
    var onTooltipRefresh: ((_ tooltipText: String?) -> Void)?

    private init() {}

    var isRunning: Bool { phase != .idle }

    func toggle() {
        if isRunning { stop() } else { startFocus() }
    }

    func startFocus() {
        beginPhase(.focus, duration: Self.focusDuration, statusText: "Focus 25:00")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        phaseEndsAt = nil
        onTooltipRefresh?(nil)
        onPhaseStart?(.idle, "")
    }

    private func beginPhase(_ newPhase: Phase, duration: TimeInterval, statusText: String) {
        timer?.invalidate()
        phase = newPhase
        phaseEndsAt = Date().addingTimeInterval(duration)
        onPhaseStart?(newPhase, statusText)
        refreshTooltip()
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
            refreshTooltip()
        }
    }

    private func finishCurrentPhase() {
        timer?.invalidate()
        timer = nil
        let just = phase
        switch just {
        case .focus:
            onPhaseEnd?(just, "Focus done — 5 min break")
            beginPhase(.shortBreak, duration: Self.shortBreakDuration, statusText: "Break 5:00")
        case .shortBreak:
            onPhaseEnd?(just, "Break done — start another focus?")
            phase = .idle
            phaseEndsAt = nil
            onTooltipRefresh?(nil)
        case .idle:
            break
        }
    }

    private func refreshTooltip() {
        guard let phaseEndsAt else { onTooltipRefresh?(nil); return }
        let remaining = max(0, phaseEndsAt.timeIntervalSinceNow)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        let label = phase == .focus ? "Focus" : "Break"
        onTooltipRefresh?(String(format: "%@ %d:%02d", label, mins, secs))
    }

    /// Menu item title — lets the right-click menu read the live state
    /// without leaking the Phase enum to AppKit code.
    var menuTitle: String {
        switch phase {
        case .idle:       return "Start Pomodoro"
        case .focus:      return "Stop Pomodoro (focusing)"
        case .shortBreak: return "Stop Pomodoro (on break)"
        }
    }
}


// MARK: - Quick Note

/// Borderless panel for capturing a one-line thought. Saves to
/// `~/Orbit/notes/YYYY-MM-DD.md` with each entry timestamped, so a day's
/// notes accumulate in one file rather than fragmenting the workspace.
@MainActor
final class QuickNoteController: NSObject, NSWindowDelegate {
    static let shared = QuickNoteController()

    private var panel: NSPanel?
    private var textField: NSTextField?

    private override init() { super.init() }

    func show() {
        if panel != nil { panel?.makeKeyAndOrderFront(nil); return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled, .closable, .borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick note"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let container = NSView(frame: panel.contentLayoutRect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.96).cgColor
        container.layer?.cornerRadius = 12
        panel.contentView = container

        let field = NSTextField(frame: NSRect(x: 16, y: 24, width: 448, height: 32))
        field.placeholderString = "What's the note? (Enter to save, Esc to cancel)"
        field.font = NSFont.systemFont(ofSize: 14)
        field.textColor = .white
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(saveNote(_:))
        container.addSubview(field)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 240
            let y = frame.midY + 80
            panel.setFrame(NSRect(x: x, y: y, width: 480, height: 80), display: true)
        }

        self.panel = panel
        self.textField = field

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        field.becomeFirstResponder()
    }

    @objc private func saveNote(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { close(); return }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Orbit").appendingPathComponent("notes")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let day = ISO8601DateFormatter.dayFormatter.string(from: Date())
        let file = dir.appendingPathComponent("\(day).md")
        let stamp = ISO8601DateFormatter.timeFormatter.string(from: Date())
        let line = "- \(stamp) — \(text)\n"

        if let data = line.data(using: .utf8) {
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
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
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
@MainActor
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
/// it doesn't yet exist so the menu item never silently no-ops.
@MainActor
enum OpenOrbitFolder {
    static func reveal() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Orbit")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

import AppKit
import EventKit
import Foundation

/// Refreshes the character's hover tooltip with the user's next calendar
/// event. Quiet by design — the tooltip only appears when the user hovers
/// the character. Permission is requested lazily (first refresh) and the
/// poller short-circuits gracefully when access is denied or restricted.
///
/// Polling cadence is 5 minutes — calendar events don't change often
/// enough to justify tighter loops, and EventKit access on macOS will
/// happily evict the cache between calls.
final class CalendarTooltipProvider {
    static let shared = CalendarTooltipProvider()

    private let store = EKEventStore()
    private var timer: Timer?
    private var hasRequestedAccess = false

    /// Hooked by LilAgentsController so the provider can update the
    /// character view's `toolTip` without coupling to AppKit types here.
    var onTooltipText: ((_ text: String?) -> Void)?

    private init() {}

    /// Begin polling. Idempotent — calling twice is safe.
    func start() {
        if timer != nil { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onTooltipText?(nil)
    }

    private func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            updateNextEvent()
        case .writeOnly:
            // Write-only access cannot read events; skip silently.
            onTooltipText?(nil)
        case .notDetermined:
            requestAccessOnce()
        case .denied, .restricted:
            onTooltipText?(nil)
        @unknown default:
            onTooltipText?(nil)
        }
    }

    private func requestAccessOnce() {
        if hasRequestedAccess { return }
        hasRequestedAccess = true
        // Deployment target is macOS 14, so the post-Ventura full-access
        // API is the only path — no fallback to the deprecated
        // `requestAccess(to:)` from earlier macOS releases.
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                if granted { self?.updateNextEvent() }
            }
        }
    }

    private func updateNextEvent() {
        let now = Date()
        // 4-hour window — far enough to catch the next meeting on a
        // light morning, narrow enough that we don't chatter about
        // events that are still hours away.
        let end = now.addingTimeInterval(4 * 3600)
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
        guard let next = upcoming.first else {
            onTooltipText?(nil)
            return
        }

        let title = (next.title ?? "Untitled event").trimmingCharacters(in: .whitespaces)
        onTooltipText?("Next: \(title) · \(Self.timeLabel(for: next.startDate, relativeTo: now))")
    }

    private static func timeLabel(for start: Date?, relativeTo now: Date) -> String {
        guard let start else { return "soon" }
        let delta = start.timeIntervalSince(now)
        if delta < 60 {
            return "now"
        }
        if delta < 60 * 60 {
            let mins = Int(delta / 60)
            return "in \(mins) min\(mins == 1 ? "" : "s")"
        }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "at \(f.string(from: start))"
    }
}

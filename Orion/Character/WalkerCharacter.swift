import AppKit
import Lottie

final class WalkerCharacter {
    let videoName: String
    var window: NSWindow!
    var imageView: NSImageView!

    let displayHeight: CGFloat = 96
    let displayWidth: CGFloat = 96

    var accelStart: CFTimeInterval = 3.0
    var fullSpeedStart: CFTimeInterval = 3.75
    var decelStart: CFTimeInterval = 7.5
    var walkStop: CFTimeInterval = 8.25
    var walkAmountRange: ClosedRange<CGFloat> = 0.25...0.5
    var yOffset: CGFloat = 0
    var flipXOffset: CGFloat = 0
    var characterColor: NSColor = .gray

    var walkStartTime: CFTimeInterval = 0
    var positionProgress: CGFloat = 0.0
    var isWalking = false
    var isPaused = true
    var pauseEndTime: CFTimeInterval = 0
    var movementLocked = false
    var goingRight = true
    var walkStartPos: CGFloat = 0.0
    var walkEndPos: CGFloat = 0.0
    var currentTravelDistance: CGFloat = 500.0
    var walkStartPixel: CGFloat = 0.0
    var walkEndPixel: CGFloat = 0.0

    var isOnboarding = false
    var isIdleForPopover = false
    /// When true, the chat popover was summoned from the menubar status
    /// item (via `ChatPopoverController`) rather than by clicking the
    /// sprite. In that mode the popover is anchored under the menubar
    /// button, so the per-tick `updatePopoverPosition()` (which re-anchors
    /// the window above the sprite's head) must NOT run — otherwise the
    /// window would snap back to the sprite on the next display-link tick.
    /// Additive flag: defaults false, so the sprite's own popover flow is
    /// completely unaffected.
    var isMenubarAnchored = false
    var popoverWindow: NSWindow?
    var terminalView: TerminalView?
    var claudeSession: ClaudeSession?
    var clickOutsideMonitor: Any?
    var escapeKeyMonitor: Any?
    weak var controller: OrionController?
    var themeOverride: PopoverTheme?
    var thinkingBubbleWindow: NSWindow?
    var focusedExpert: ResponderExpert?
    var representedExpert: ResponderExpert?
    var isCompanionAvatar = false
    var handoffEffectWindow: NSWindow?
    var handoffEffectAnimationView: LottieAnimationView?
    var expertNameWindow: NSWindow?
    var popoverTitleLabel: NSTextField?
    var popoverSubtitleLabel: NSTextField?
    var popoverExpertSwitcherButton: HoverButton?
    var popoverReturnButton: NSButton?
    var popoverSettingsButton: HoverButton?
    var popoverToolboxButton: HoverButton?
    /// The SwiftUI toolbox overlay (added on first toolbox-button tap,
    /// reused thereafter). nil when not yet built.
    var popoverToolboxOverlay: NSView?
    var popoverExpandButton: HoverButton?
    var popoverPinButton: HoverButton?
    var popoverCloseButton: HoverButton?
    var expertSwitcherPopover: NSPopover?
    var isPopoverExpanded = false
    var isPopoverPinned = false
    // Total popover window dimensions. The bubble body is
    // `defaultPopoverHeight - popoverTailHeight` tall; the bottom
    // `popoverTailHeight` pixels host the speech-bubble tail pointing
    // down at the character. `defaultPopoverWidth` is the rest-state
    // width — the expand toggle widens to 1.5× and lengthens height to
    // a screen-fit value, then collapses back to these defaults.
    static let defaultPopoverWidth: CGFloat = 468
    static let defaultPopoverHeight: CGFloat = 574
    static let popoverTailHeight: CGFloat = 14
    static let popoverTailWidth: CGFloat = 28

    // Backing layer for the speech-bubble outline (rounded body + tail
    // as one continuous shape). Stored so we can rebuild its path when
    // the popover resizes.
    var popoverBubbleShape: CAShapeLayer?

    // ── Sleep state machine ─────────────────────────────────────────
    // After ~2–4 minutes of no interaction, Orion curls up for a
    // 30–90s nap (`main-sleeping.gif`). Any click / popover open / drag
    // wakes him immediately; otherwise he wakes on his own, paces, and
    // delivers an ambient bubble within ~8–25s of standing back up.
    //
    // Cadence iteration history:
    //   - Pre-v0.1.21: 1.5–4 min awake, 30–120s sleep, but the wake
    //     bug made him cycle in and out within a single tick.
    //   - v0.1.21:     3–6 min awake, 20–60s sleep — fixed the wake
    //                  bug but Sir reported he sleeps too rarely now.
    //   - v0.1.35:     2–4 min awake, 30–90s sleep — splits the
    //                  difference. Steady-state target ~70% awake,
    //                  ~30% asleep when truly idle. Active use still
    //                  prevents sleep entirely (each interaction resets
    //                  the timer), which is correct behaviour.
    var sleepingImage: NSImage?
    var isSleeping: Bool = false
    var lastInteractionAt: CFTimeInterval = CACurrentMediaTime()
    var idleSleepThreshold: TimeInterval = TimeInterval.random(in: 120...240)
    var wakeAt: CFTimeInterval = 0
    static let minIdleBeforeSleep: TimeInterval = 120     // 2 min
    static let maxIdleBeforeSleep: TimeInterval = 240     // 4 min
    static let minSleepDuration: TimeInterval = 30
    static let maxSleepDuration: TimeInterval = 90

    // ── Idle facing variety ────────────────────────────────────────
    // During long idle pauses, periodically re-roll between front and
    // back facing so Orion doesn't just stare at the camera the
    // whole time. Driven from the per-tick update().
    var nextIdleFacingRollAt: CFTimeInterval = 0

    // ── Ambient bubbles ────────────────────────────────────────────
    // While idle (no popover, no chat in flight, awake, not focused on
    // an expert) Orion periodically pipes up with a short Justin/
    // Orbit-voice comment — a CRM micro-tip, a deliverability gripe,
    // or a dry remark. Cadence is a randomised 90–240s gap between
    // bubbles. Each bubble lingers ~12s so Sir actually has time to
    // read it.
    // First bubble fires 20–90s after launch — Sir wanted Orion
    // to introduce himself sooner rather than waiting 1–3 minutes.
    var nextAmbientBubbleAt: CFTimeInterval = CACurrentMediaTime() + TimeInterval.random(in: 20...90)
    var ambientBubbleExpiresAt: CFTimeInterval = 0
    /// When true, the bubble surface is being driven by an external
    /// producer (Pomodoro countdown today; potentially other persistent
    /// status sources later). The 60fps `updateThinkingBubble` tick
    /// must not call `hideBubble()` while this is set, otherwise the
    /// bubble flashes between the producer's per-second updates.
    var pomodoroBubbleHold: Bool = false
    /// While Pomodoro is in a focus phase, suppress the idle-threshold
    /// auto-sleep so Orion stays awake even with no mouse activity. The
    /// chat / popover wake triggers continue to work normally.
    var pomodoroForceAwake: Bool = false
    /// While Pomodoro is in a break phase, suppress the `wakeAt` timer
    /// auto-wake so Orion stays asleep for the full break. User-
    /// initiated wakes (chat busy, popover open) still take effect.
    var pomodoroForceAsleep: Bool = false
    var lastAmbientLineIndex: Int = -1
    var isAmbientLLMRequestInFlight: Bool = false
    /// Text of the ambient bubble currently visible. Set in
    /// showAmbientLine, cleared when the bubble expires or hides.
    /// Read by openPopover so a click on Orion while a tip is
    /// showing pre-fills the composer with a "tell me more" prompt
    /// and sends — turning the passing observation into a chat
    /// thread on demand.
    var currentAmbientLineText: String?
    // Steady-state gap between bubbles. Average ~97s = ~37 bubbles/hr
    // when Orion is idle. Tighter than this risks stacking — the
    // ambient LLM call takes up to 25s and we don't want a new bubble
    // queueing while the previous one is still rendering or its LLM
    // dispatch is still in flight.
    static let minAmbientGap: TimeInterval = 45
    static let maxAmbientGap: TimeInterval = 150
    // Linger time on screen. 25s — long enough for Sir to read a
    // two-line CRM/lifecycle observation, decide whether it's worth
    // drilling into, and click Orion to ask for more before the
    // bubble fades. Click-to-drill-in only works while the bubble is
    // visible, so this dictates the click window too.
    static let ambientBubbleLinger: TimeInterval = 25

    /// Build the speech-bubble outline as a single closed CGPath:
    /// rounded body on top + downward-pointing tail below. Drawing the
    /// whole thing as one path eliminates the visible seam where a
    /// separate body and tail used to meet.
    ///
    /// `tailCenterX` is the X (in popover-local coords) where the
    /// tail's apex should land. Pass nil to default to the popover's
    /// horizontal centre. The expanded-popover clamping path passes
    /// the character's actual screen X minus the popover's origin X
    /// so the tail keeps pointing at the character even after the
    /// popover gets bumped sideways to fit on-screen.
    /// When `tailOnTop` is true the tail jut points UP (apex at
    /// y=size.height) and the rounded body occupies the bottom of the
    /// rect (y=0 up to y=size.height−tailHeight). This is the menubar-
    /// anchored layout: the popover hangs below the status-item icon at
    /// the top of the screen, so the beak must point up toward it.
    /// Default (false) keeps the original tail-down sprite layout.
    static func bubbleShellPath(
        size: CGSize,
        tailHeight: CGFloat,
        tailWidth: CGFloat,
        cornerRadius r: CGFloat,
        tailCenterX: CGFloat? = nil,
        tailOnTop: Bool = false
    ) -> CGPath {
        // Cocoa flipped Y: origin bottom-left. Tail-down (default): body
        // sits from y=tailHeight up to y=size.height; tail apex points
        // down to y=0. Tail-up: body sits from y=0 up to y=size.height−
        // tailHeight; tail apex points up to y=size.height. Path traces
        // clockwise, rounds each corner via tangent-end arcs, and breaks
        // the tail-side edge at the tail attachment points.
        let w = size.width
        let h = size.height
        let halfTail = tailWidth / 2
        // Clamp the tail position so its base never overlaps the
        // rounded corners — leaves a small margin (`r + halfTail + 4`)
        // on each side. Without this an off-centre tail in a narrow
        // popover would render with a broken/jagged corner arc.
        let minCx = r + halfTail + 4
        let maxCx = w - r - halfTail - 4
        let requestedCx = tailCenterX ?? (w / 2)
        let cx = min(maxCx, max(minCx, requestedCx))

        let p = CGMutablePath()

        if tailOnTop {
            // Body occupies the bottom; tail juts up from the top edge.
            let bodyTop = h - tailHeight
            let bodyBottom: CGFloat = 0
            // Trace clockwise from the left edge near the top, break the
            // TOP edge for the upward tail, then round the lower corners.
            p.move(to: CGPoint(x: 0, y: bodyTop - r))
            p.addArc(tangent1End: CGPoint(x: 0, y: bodyTop), tangent2End: CGPoint(x: cx - halfTail, y: bodyTop), radius: r)
            p.addLine(to: CGPoint(x: cx - halfTail, y: bodyTop))
            p.addLine(to: CGPoint(x: cx, y: h))
            p.addLine(to: CGPoint(x: cx + halfTail, y: bodyTop))
            p.addArc(tangent1End: CGPoint(x: w, y: bodyTop), tangent2End: CGPoint(x: w, y: bodyTop - r), radius: r)
            p.addArc(tangent1End: CGPoint(x: w, y: bodyBottom), tangent2End: CGPoint(x: w - r, y: bodyBottom), radius: r)
            p.addArc(tangent1End: CGPoint(x: 0, y: bodyBottom), tangent2End: CGPoint(x: 0, y: bodyBottom + r), radius: r)
            p.closeSubpath()
            return p
        }

        let bodyBottom = tailHeight
        let bodyTop = h
        p.move(to: CGPoint(x: 0, y: bodyTop - r))
        p.addArc(tangent1End: CGPoint(x: 0, y: bodyTop), tangent2End: CGPoint(x: r, y: bodyTop), radius: r)
        p.addArc(tangent1End: CGPoint(x: w, y: bodyTop), tangent2End: CGPoint(x: w, y: bodyTop - r), radius: r)
        p.addArc(tangent1End: CGPoint(x: w, y: bodyBottom), tangent2End: CGPoint(x: w - r, y: bodyBottom), radius: r)
        p.addLine(to: CGPoint(x: cx + halfTail, y: bodyBottom))
        p.addLine(to: CGPoint(x: cx, y: 0))
        p.addLine(to: CGPoint(x: cx - halfTail, y: bodyBottom))
        p.addArc(tangent1End: CGPoint(x: 0, y: bodyBottom), tangent2End: CGPoint(x: 0, y: bodyBottom + r), radius: r)
        p.closeSubpath()
        return p
    }

    var isClaudeBusy: Bool { claudeSession?.isBusy ?? false }

    var directionalImages: [WalkerFacing: NSImage] = [:]
    var persona: WalkerPersona = .orion

    var lastPhraseUpdate: CFTimeInterval = 0
    var currentPhrase = ""
    var completionBubbleExpiry: CFTimeInterval = 0
    var showingCompletion = false
    var phraseAnimating = false
    var currentActivityStatus = ""
    var liveStatusFallbackTimer: Timer?
    /// Drives the gravity-fall animation when the user releases a drag.
    /// Held here (rather than scoped to `endHorizontalDrag`) so we can
    /// invalidate it if the user grabs Orion again mid-fall —
    /// otherwise two animations would race for the window frame.
    var dropTimer: Timer?
    var lastLiveStatusEventAt: Date?
    var liveStatusFallbackIndex = 0
    var isDraggingHorizontally = false
    var usesExpandedHorizontalRange = false

    init(videoName: String) {
        self.videoName = videoName
    }
}

import AppKit

// PHASE 2 — the ambient speech-bubble system (thinking bubble, completion
// bubble, idle Orbit-voice "ambient lines" via LLM, sleep/wake banter) was
// SPRITE decoration: a borderless bubble window pinned above the walking
// character. With the visible sprite removed it has nowhere to anchor.
//
// What survives here, functional:
//   • the completion-/selection-SOUND machinery — `playSelectionSound()`
//     is fired from the chat UI (TerminalView: dictation, suggestion
//     pick, copy, send) and `playCompletionSound()` from the chat turn-
//     complete handler. These are genuine chat affordances, NOT sprite
//     decoration, so they keep their real implementation.
//   • `soundsEnabled` — toggled by the menubar "Sounds" item.
//
// Everything else (showBubble / hideBubble / showCompletionBubble /
// updateThinkingPhrase) is retained as an inert no-op so the kept call
// sites in WalkerCharacterPopover + WalkerCharacterSessionWiring keep
// resolving without edits. The 60fps `updateThinkingBubble`, the ambient-
// line LLM generator, and the bubble tap/hover handlers were only ever
// driven by the now-deleted movement tick loop, so they are gone.
extension WalkerCharacter {

    // ── Sound (kept functional — used by the chat UI) ───────────────
    private static let completionSounds: [(name: String, ext: String)] = [
        ("ping-aa", "mp3"), ("ping-bb", "mp3"), ("ping-cc", "mp3"),
        ("ping-dd", "mp3"), ("ping-ee", "mp3"), ("ping-ff", "mp3"),
        ("ping-gg", "mp3"), ("ping-hh", "mp3"), ("ping-jj", "m4a")
    ]
    private static var lastSoundIndex: Int = -1
    static var soundsEnabled = true

    static func playSelectionSound() {
        guard Self.soundsEnabled else { return }
        var idx: Int
        repeat {
            idx = Int.random(in: 0..<Self.completionSounds.count)
        } while idx == Self.lastSoundIndex && Self.completionSounds.count > 1
        Self.lastSoundIndex = idx

        let s = Self.completionSounds[idx]
        if let url = Bundle.main.url(forResource: s.name, withExtension: s.ext, subdirectory: "Sounds"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        }
    }

    func playCompletionSound() {
        Self.playSelectionSound()
    }

    // ── Bubble surface (no-ops — the sprite bubble is gone) ─────────
    func showBubble(text: String, isCompletion: Bool, multiline: Bool = true, tint: NSColor? = nil) {
        // No-op: the floating speech bubble was anchored to the sprite.
    }

    func hideBubble() {
        // No-op.
    }

    func showCompletionBubble() {
        // No-op.
    }

    func updateThinkingPhrase() {
        // No-op.
    }
}

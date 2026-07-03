import AppKit

// PHASE 2 — persona-swap visuals (the cross-fade scale animation on the
// sprite GIF, plus the Lottie/CAShapeLayer "smoke cloud" handoff effect
// anchored over the walking character) were pure SPRITE decoration. With
// the visible sprite removed there is nothing on screen to animate, so
// both entry points are retained as inert no-ops. They are still called
// from WalkerCharacterCore.setPersona() during expert focus/return, which
// itself is now largely vestigial but harmless.
extension WalkerCharacter {
    func animatePersonaSwap() {
        // No-op: no visible sprite image view to animate.
    }

    func playHandoffEffect(from previousPersona: WalkerPersona, to newPersona: WalkerPersona) {
        // No-op: the floating handoff smoke/Lottie effect was anchored to
        // the sprite window, which no longer exists.
    }
}

import AppKit

// PHASE 2 — the floating "Ask <Expert>" name tag was a SPRITE decoration
// (a small borderless window pinned above the walking character's head).
// With the visible sprite removed, the tag has nowhere to anchor and no
// purpose. These methods are retained as inert no-ops so the many call
// sites in the kept chat/session code (WalkerCharacterSessionWiring,
// WalkerCharacterCore, WalkerCharacterPopoverWindow) keep resolving
// without edits. `expertNameWindow` is never created, so both are cheap.
extension WalkerCharacter {
    func updateExpertNameTag() {
        // No-op: the sprite name-tag window is gone.
    }

    func hideExpertNameTag() {
        // Defensive: nothing to hide, but tolerate a stale window if one
        // ever existed.
        if expertNameWindow?.isVisible ?? false {
            expertNameWindow?.orderOut(nil)
        }
    }
}

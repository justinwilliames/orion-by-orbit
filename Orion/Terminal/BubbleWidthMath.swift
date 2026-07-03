import Foundation
import CoreGraphics

/// Pure math the chat bubble layout depends on. Extracted here so
/// the test suite can pin the formula — the same function silently
/// killed two previous expand fixes when wrong inputs or wrong
/// thresholds were used.
///
/// The contract Sir set:
///   - **Default popover** must match the original Lil-Lenny fork:
///     bubbles cap at the historical 380pt for conversational
///     line-length, with a visible right gutter against the column.
///   - **Expanded popover** is the only mode that grows bubbles —
///     the user explicitly asked for more horizontal real estate,
///     so we honour that up to a 720pt soft cap (past which line
///     length hurts readability more than space helps).
enum BubbleWidthMath {
    /// Lower floor — first-launch layout with frame near zero
    /// shouldn't crush bubbles into something unreadable.
    static let minWidth: CGFloat = 280

    /// Conversational cap that matches the upstream Lil-Lenny fork
    /// behaviour. Used in default popover mode.
    static let defaultCap: CGFloat = 380

    /// Soft cap once the popover is expanded.
    static let maxExpandedWidth: CGFloat = 720

    /// Column width above which we treat the popover as "expanded"
    /// and let bubbles grow. The default-mode column lands around
    /// 400pt (popover ≈ 432pt minus 16pt padding × 2); the
    /// expanded-mode column is ~50% wider, well past 600pt. 460pt
    /// sits comfortably between, so manual window resizes near the
    /// default size still hold the historical cap.
    static let expansionThreshold: CGFloat = 460

    /// Given the TerminalView's current frame width and the side
    /// padding it carves off, return the column width a chat bubble
    /// should target.
    static func maxBubbleWidth(forFrameWidth frameWidth: CGFloat, sidePadding: CGFloat) -> CGFloat {
        let columnWidth = max(0, frameWidth - sidePadding * 2)

        // First-layout frames where the column is below our floor
        // get clamped up so bubbles aren't a sliver.
        guard columnWidth >= minWidth else { return minWidth }

        // Default popover: hold the historical 380pt cap. Use
        // `min(defaultCap, columnWidth)` so a column slightly under
        // the cap (rare but possible) doesn't try to oversize.
        if columnWidth <= expansionThreshold {
            return min(defaultCap, columnWidth)
        }

        // Expanded popover: grow with available space, capped at the
        // soft readability ceiling.
        return min(maxExpandedWidth, columnWidth)
    }
}

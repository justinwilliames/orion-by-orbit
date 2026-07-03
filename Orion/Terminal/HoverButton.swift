import AppKit

class HoverButton: NSButton {
    var normalBg: CGColor = NSColor.clear.cgColor
    var hoverBg: CGColor = NSColor.clear.cgColor
    var horizontalContentPadding: CGFloat = 0
    var verticalContentPadding: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        let titleSize = attributedTitle.length > 0
            ? attributedTitle.size()
            : super.intrinsicContentSize
        let base = super.intrinsicContentSize
        return NSSize(
            width: max(base.width, titleSize.width) + horizontalContentPadding * 2,
            height: max(base.height, titleSize.height) + verticalContentPadding * 2
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().layer?.backgroundColor = hoverBg
        }
        if let toolTip, !toolTip.isEmpty {
            HoverTooltipController.shared.show(toolTip, from: self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().layer?.backgroundColor = normalBg
        }
        HoverTooltipController.shared.hide()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        HoverTooltipController.shared.hide()
        super.mouseDown(with: event)
    }
}

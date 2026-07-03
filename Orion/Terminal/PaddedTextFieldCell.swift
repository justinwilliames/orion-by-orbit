import AppKit

class PaddedTextFieldCell: NSTextFieldCell {
    private let inset = NSSize(width: 8, height: 0)
    var fieldBackgroundColor: NSColor?
    var fieldCornerRadius: CGFloat = 4

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if let bg = fieldBackgroundColor {
            let path = NSBezierPath(roundedRect: cellFrame, xRadius: fieldCornerRadius, yRadius: fieldCornerRadius)
            bg.setFill()
            path.fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: rect)
    }

    private func centeredTextRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect).insetBy(dx: inset.width, dy: inset.height)
        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let centeredY = base.origin.y + max(0, floor((base.height - textHeight) / 2) - 1)
        return NSRect(x: base.origin.x, y: centeredY, width: base.width, height: textHeight)
    }

    private func configureEditor(_ textObj: NSText) {
        if let color = textColor {
            textObj.textColor = color
        }
        if let tv = textObj as? NSTextView {
            tv.insertionPointColor = textColor ?? .textColor
            tv.drawsBackground = false
            tv.backgroundColor = .clear
        }
        textObj.font = font
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        configureEditor(textObj)
        super.edit(withFrame: centeredTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        configureEditor(textObj)
        super.select(withFrame: centeredTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

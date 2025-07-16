// ColorSwatchView.swift
import Cocoa

class ColorSwatchView: NSView {
    var color: NSColor = .black {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        color.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 6, yRadius: 6)
        path.fill()

        NSColor.black.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

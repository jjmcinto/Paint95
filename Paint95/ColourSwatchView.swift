// ColourSwatchView.swift
import Cocoa

class ColourSwatchView: NSView {
    var colour: NSColor = .black {
        didSet {
            needsDisplay = true
        }
    }

    var onClick: (() -> Void)?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        colour.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 6, yRadius: 6)
        path.fill()

        NSColor.black.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
    
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

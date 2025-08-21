// ColourPaletteView.swift
import Cocoa

protocol ColourPaletteDelegate: AnyObject {
    func colourSelected(_ colour: NSColor)
}

class ColourPaletteView: NSView {
    weak var delegate: ColourPaletteDelegate?

    var selectedColour: NSColor = .black {
        didSet { needsDisplay = true }
    }
    
    let colours: [NSColor] = [
        .black, .darkGray, .gray, .white,
        .red, .green, .blue, .cyan,
        .yellow, .magenta, .orange, .brown,
        .systemPink, .systemIndigo, .systemTeal, .systemPurple
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let squareSize = NSSize(width: 20, height: 20)
        for (index, colour) in colours.enumerated() {
            let x = CGFloat(index % 8) * (squareSize.width + 2)
            let y = CGFloat(index / 8) * (squareSize.height + 2)
            let rect = NSRect(origin: CGPoint(x: x, y: y), size: squareSize)

            colour.setFill()
            rect.fill()

            NSColor.black.setStroke()
            rect.frame(withWidth: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let c = sampledColour(at: p) {
            delegate?.colourSelected(c)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let c = sampledColour(at: p) {
            delegate?.colourSelected(c)
            needsDisplay = true
        }
    }
    
    private func sampledColour(at viewPoint: NSPoint) -> NSColor? {
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)

        let scaleX = CGFloat(rep.pixelsWide) / bounds.width
        let scaleY = CGFloat(rep.pixelsHigh) / bounds.height

        let px = Int((viewPoint.x * scaleX).rounded(.down))
        let py: Int = {
            if isFlipped {
                return Int((viewPoint.y * scaleY).rounded(.down))
            } else {
                return Int(((bounds.height - viewPoint.y) * scaleY).rounded(.down))
            }
        }()

        guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
              let c = rep.colorAt(x: px, y: py) else { return nil }

        return c.usingColorSpace(.deviceRGB)
    }
}

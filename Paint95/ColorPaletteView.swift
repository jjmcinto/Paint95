// ColorPaletteView.swift
import Cocoa

protocol ColorPaletteDelegate: AnyObject {
    func colorSelected(_ color: NSColor)
}

class ColorPaletteView: NSView {
    weak var delegate: ColorPaletteDelegate?

    let colors: [NSColor] = [
        .black, .darkGray, .gray, .white,
        .red, .green, .blue, .cyan,
        .yellow, .magenta, .orange, .brown,
        NSColor.systemPink, NSColor.systemIndigo, NSColor.systemTeal, NSColor.systemPurple
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let squareSize = NSSize(width: 20, height: 20)
        for (index, color) in colors.enumerated() {
            let x = CGFloat(index % 8) * (squareSize.width + 2)
            let y = CGFloat(index / 8) * (squareSize.height + 2)
            let rect = NSRect(origin: CGPoint(x: x, y: y), size: squareSize)

            color.setFill()
            rect.fill()

            NSColor.black.setStroke()
            rect.frame(withWidth: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / 22)
        let row = Int(point.y / 22)
        let index = row * 8 + col
        if colors.indices.contains(index) {
            delegate?.colorSelected(colors[index])
        }
    }
}

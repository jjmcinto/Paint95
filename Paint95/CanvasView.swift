// CanvasView.swift
import Cocoa

class CanvasView: NSView {
    var currentTool: PaintTool = .pencil
    var currentColor: NSColor = .black
    var backgroundColor: NSColor = .white
    
    private var image: NSImage = NSImage(size: NSSize(width: 800, height: 600))
    private var lastPoint: NSPoint?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initializeImage()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initializeImage()
    }
    
    private func initializeImage() {
        image.lockFocus()
        backgroundColor.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: self.bounds)
    }
    
    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = lastPoint else { return }
        let end = convert(event.locationInWindow, from: nil)

        image.lockFocus()
        currentColor.setStroke()
        
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = currentTool == .brush ? 4.0 : 1.0
        path.stroke()
        image.unlockFocus()
        
        lastPoint = end
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastPoint = nil
    }

    func clearCanvas() {
        image.lockFocus()
        backgroundColor.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        needsDisplay = true
    }
}

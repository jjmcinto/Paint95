import Cocoa

class CanvasView: NSView {

    var currentTool: PaintTool = .pencil
    var currentColor: NSColor = .black
    var strokeWidth: CGFloat = 1.0

    private var lastPoint: CGPoint?
    private var tempPath: NSBezierPath?
    private var image = NSImage(size: NSSize(width: 800, height: 600))

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Always paint a white background
        NSColor.white.setFill()
        bounds.fill()

        // Draw the image contents
        image.draw(in: bounds)

        // Draw temp shape (line/rect/ellipse) if active
        currentColor.setStroke()
        tempPath?.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)

        if currentTool == .fill {
            // TODO: Fill logic
        } else if currentTool == .colorPicker {
            // TODO: Color picker logic
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = lastPoint else { return }
        let end = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .pencil, .brush, .eraser:
            drawLine(from: start, to: end)
            lastPoint = end
        case .line, .rect, .ellipse:
            tempPath = shapePath(from: start, to: end)
            needsDisplay = true
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = lastPoint else { return }
        let end = convert(event.locationInWindow, from: nil)

        if [.line, .rect, .ellipse].contains(currentTool) {
            let path = shapePath(from: start, to: end)
            drawShape(path)
        }

        lastPoint = nil
        tempPath = nil
        needsDisplay = true
    }

    private func drawLine(from start: CGPoint, to end: CGPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        switch currentTool {
        case .brush:
            path.lineWidth = 4.0
        case .eraser:
            path.lineWidth = 12.0 // 3× the brush width
        default:
            path.lineWidth = strokeWidth
        }

        image.lockFocus()

        if currentTool == .eraser {
            NSColor.white.setStroke()
        } else {
            currentColor.setStroke()
        }
        
        path.stroke()
        image.unlockFocus()

        needsDisplay = true
    }

    private func shapePath(from start: CGPoint, to end: CGPoint) -> NSBezierPath {
        let rect = NSRect(x: min(start.x, end.x),
                          y: min(start.y, end.y),
                          width: abs(end.x - start.x),
                          height: abs(end.y - start.y))

        switch currentTool {
        case .line:
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = strokeWidth
            return path
        case .rect:
            let path = NSBezierPath(rect: rect)
            path.lineWidth = strokeWidth
            return path
        case .ellipse:
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = strokeWidth
            return path
        default:
            return NSBezierPath()
        }
    }

    private func drawShape(_ path: NSBezierPath) {
        currentColor.setStroke()

        image.lockFocus()
        currentColor.setStroke()
        path.stroke()
        image.unlockFocus()
    }

    func clearCanvas() {
        image = NSImage(size: bounds.size)
        needsDisplay = true
    }
}

import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func didPickColor(_ color: NSColor)
}

class CanvasView: NSView {

    // MARK: - Properties

    private var bitmapRep: NSBitmapImageRep!
    private var canvasImage: NSImage {
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    private var currentPath: NSBezierPath?
    private var startPoint: NSPoint = .zero
    private var endPoint: NSPoint = .zero

    var currentTool: PaintTool = .pencil
    var currentColor: NSColor = .black
    var delegate: CanvasViewDelegate?

    // MARK: - Init

    override func awakeFromNib() {
        super.awakeFromNib()
        setupCanvasImage()
    }

    private func setupCanvasImage() {
        let size = bounds.size

        bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        bitmapRep.size = size

        // Fill with white
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        canvasImage.draw(in: bounds)
    }

    func clearCanvas() {
        setupCanvasImage()
        setNeedsDisplay(bounds)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        endPoint = location

        switch currentTool {
        case .pencil, .brush, .eraser:
            let path = NSBezierPath()
            path.move(to: location)
            currentPath = path
            drawPoint(location)

        case .line, .rect, .ellipse, .roundRect:
            currentPath = nil  // Shapes drawn on mouseUp

        case .fill:
            // TODO: Flood fill
            break

        case .colorPicker:
            let picked = color(at: location)
            delegate?.didPickColor(picked)

        case .select:
            // TODO: Selection logic
            break

        case .curve:
            // TODO: Bézier curve logic
            break

        case .text:
            // TODO: Text placement
            break

        case .zoom:
            // TODO: Zoom logic
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        endPoint = location

        switch currentTool {
        case .pencil, .brush, .eraser:
            currentPath?.line(to: location)
            drawPoint(location)

        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        endPoint = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .line:
            drawLine(from: startPoint, to: endPoint)

        case .rect:
            drawShape(path: NSBezierPath(rect: rectBetween(startPoint, endPoint)))

        case .ellipse:
            drawShape(path: NSBezierPath(ovalIn: rectBetween(startPoint, endPoint)))

        case .roundRect:
            let rect = rectBetween(startPoint, endPoint)
            let radius: CGFloat = 10
            drawShape(path: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius))

        default:
            break
        }

        currentPath = nil
    }

    // MARK: - Drawing Helpers

    private func drawPoint(_ point: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = context

            let path = currentPath ?? NSBezierPath()
            switch currentTool {
            case .brush:
                currentColor.setStroke()
                path.lineWidth = 2
                path.stroke()

            case .pencil:
                currentColor.setStroke()
                path.lineWidth = 1
                path.stroke()

            case .eraser:
                NSColor.white.setStroke()
                path.lineWidth = 6
                path.stroke()

            default:
                break
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        setNeedsDisplay(bounds)
    }

    private func drawLine(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        drawShape(path: path)
    }

    private func drawShape(path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = context
            currentColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        setNeedsDisplay(bounds)
    }

    private func rectBetween(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        return NSRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p1.x - p2.x),
            height: abs(p1.y - p2.y)
        )
    }

    // MARK: - Color Sampling

    private func color(at point: NSPoint) -> NSColor {
        let x = Int(point.x)
        let y = Int(bounds.height - point.y)
        if x >= 0, y >= 0, x < bitmapRep.pixelsWide, y < bitmapRep.pixelsHigh {
            return bitmapRep.colorAt(x: x, y: y) ?? .black
        } else {
            return .black
        }
    }
}

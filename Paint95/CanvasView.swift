import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func didPickColor(_ color: NSColor)
}

struct Pixel: Hashable {
    let x: Int
    let y: Int
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
    private var floodImage: NSImage?

    var currentTool: PaintTool = .pencil
    var currentColor: NSColor = .black
    var delegate: CanvasViewDelegate?
    var paths: [(path: NSBezierPath, color: NSColor)] = []

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

        // Clear background
        NSColor.white.setFill()
        dirtyRect.fill()

        // Draw flood fill image if present
        if let flood = floodImage {
            flood.draw(in: bounds)
        }

        // Draw existing paths
        for (path, color) in paths {
            color.setStroke()
            path.stroke()
        }

        currentColor.setStroke()
        currentPath?.stroke()
    }

    func clearCanvas() {
        setupCanvasImage()
        setNeedsDisplay(bounds)
    }
    
    func renderedCanvasImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()

        // Fill white background
        NSColor.white.setFill()
        bounds.fill()

        // Draw paths
        for (path, color) in paths {
            color.setStroke()
            path.stroke()
        }

        image.unlockFocus()
        return image
    }
    
    func floodFill(from point: NSPoint, with fillColor: NSColor) {
        let width = Int(bounds.width)
        let height = Int(bounds.height)

        // Step 1: Create a writable 32-bit RGBA bitmap
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("Failed to create bitmap")
            return
        }

        // Step 2: Render the canvas into the bitmap
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(bounds)
        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else {
            print("No bitmap data available")
            return
        }

        // Step 3: Convert point and get target pixel's RGBA
        let x = Int(point.x)
        let y = Int(bounds.height - point.y) // flip Y for macOS
        guard x >= 0, x < width, y >= 0, y < height else { return }

        let offset = (y * rep.bytesPerRow) + (x * rep.samplesPerPixel)
        let startPixel = data + offset

        let targetR = startPixel[0]
        let targetG = startPixel[1]
        let targetB = startPixel[2]
        let targetA = startPixel[3]

        // If fillColor matches target, skip
        var rF: CGFloat = 0, gF: CGFloat = 0, bF: CGFloat = 0, aF: CGFloat = 0
        fillColor.usingColorSpace(.deviceRGB)?.getRed(&rF, green: &gF, blue: &bF, alpha: &aF)
        let newR = UInt8(rF * 255)
        let newG = UInt8(gF * 255)
        let newB = UInt8(bF * 255)
        let newA = UInt8(aF * 255)

        if targetR == newR && targetG == newG && targetB == newB && targetA == newA {
            print("Fill color matches target color — skipping fill")
            return
        }

        // Step 4: Flood fill algorithm using pixel bytes
        var queue = [(x, y)]

        while !queue.isEmpty {
            let (cx, cy) = queue.removeLast()
            if cx < 0 || cy < 0 || cx >= width || cy >= height {
                continue
            }

            let pixelOffset = (cy * rep.bytesPerRow) + (cx * rep.samplesPerPixel)
            let pixel = data + pixelOffset

            if pixel[0] != targetR || pixel[1] != targetG || pixel[2] != targetB || pixel[3] != targetA {
                continue
            }

            pixel[0] = newR
            pixel[1] = newG
            pixel[2] = newB
            pixel[3] = newA

            queue.append((cx + 1, cy))
            queue.append((cx - 1, cy))
            queue.append((cx, cy + 1))
            queue.append((cx, cy - 1))
        }

        // Step 5: Turn bitmap into NSImage
        let newImage = NSImage(size: bounds.size)
        newImage.lockFocus()
        rep.draw(in: bounds)
        newImage.unlockFocus()

        floodImage = newImage
        needsDisplay = true
    }


    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        endPoint = location
        floodImage = nil

        switch currentTool {
        case .pencil, .brush, .eraser:
            let path = NSBezierPath()
            path.move(to: location)
            currentPath = path
            drawPoint(location)

        case .line, .rect, .ellipse, .roundRect:
            currentPath = nil  // Shapes drawn on mouseUp

        case .fill:
            let pointInView = convert(event.locationInWindow, from: nil)
                floodFill(from: pointInView, with: currentColor)
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
        
        if let path = currentPath {
            paths.append((path, currentColor))
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
        
        if let path = currentPath {
            paths.append((path, currentColor))
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

import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func didPickColor(_ color: NSColor)
}

class CanvasView: NSView {

    weak var delegate: CanvasViewDelegate?

    var currentTool: PaintTool = .pencil
    var currentColor: NSColor = .black

    var canvasImage: NSImage? = nil
    var currentPath: NSBezierPath?
    var startPoint: NSPoint = .zero

    var drawnPaths: [(path: NSBezierPath, color: NSColor)] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.white.setFill()
        dirtyRect.fill()

        canvasImage?.draw(in: bounds)

        for (path, color) in drawnPaths {
            color.setStroke()
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        initializeCanvasIfNeeded()

        switch currentTool {
        case .eyeDropper:
            if let picked = pickColor(at: point) {
                currentColor = picked
                NotificationCenter.default.post(name: .colorPicked, object: picked)
            }

        case .pencil, .brush, .eraser:
            startPoint = point
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        case .fill:
            floodFill(from: point, with: currentColor)

        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .pencil, .brush:
            currentPath?.line(to: point)
            drawCurrentPathToCanvas()
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        case .eraser:
            currentPath?.line(to: point)
            drawCurrentPathToCanvas()
            eraseDot(at: point)         // 💥 Erase white pixel area directly
            erasePaths(at: point)       // ✂️ Remove any intersecting drawn paths
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        currentPath = nil
    }

    private func erasePaths(at point: NSPoint, radius: CGFloat = 7.5) {
        let eraserRect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        drawnPaths.removeAll { path, _ in
            path.bounds.intersects(eraserRect)
        }
    }
    
    private func drawCurrentPathToCanvas() {
        guard let path = currentPath else { return }
        initializeCanvasIfNeeded()

        // Configure path appearance before drawing
        path.lineCapStyle = .butt      // No rounded ends
        path.lineJoinStyle = .miter    // Sharp corners

        canvasImage?.lockFocus()

        switch currentTool {
        case .pencil:
            currentColor.set()
            path.lineWidth = 1
            path.stroke()
            drawnPaths.append((path.copy() as! NSBezierPath, currentColor))

        case .brush:
            currentColor.set()
            path.lineWidth = 5
            path.stroke()
            drawnPaths.append((path.copy() as! NSBezierPath, currentColor))

        case .eraser:
            path.lineCapStyle = .butt
            path.lineJoinStyle = .miter
            NSColor.white.set()
            path.lineWidth = 15
            path.stroke()
            // No need to add to drawnPaths

        default:
            break
        }

        canvasImage?.unlockFocus()
        needsDisplay = true
    }
    
    private func eraseDot(at point: NSPoint, radius: CGFloat = 7.5) {
        initializeCanvasIfNeeded()
        canvasImage?.lockFocus()
        NSColor.white.set()
        let rect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        NSBezierPath(rect: rect).fill()
        canvasImage?.unlockFocus()
    }
    
    func clearCanvas() {
        drawnPaths.removeAll()
        canvasImage = nil
        needsDisplay = true
    }

    private func initializeCanvasIfNeeded() {
        if canvasImage == nil {
            canvasImage = NSImage(size: bounds.size)
            canvasImage?.lockFocus()
            NSColor.white.set()
            NSBezierPath(rect: bounds).fill()
            canvasImage?.unlockFocus()
        }
    }

    func pickColor(at point: NSPoint) -> NSColor? {
        let flippedPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        let x = Int(flippedPoint.x)
        let y = Int(flippedPoint.y)

        guard x >= 0, y >= 0, x < Int(bounds.width), y < Int(bounds.height) else {
            print("❌ Eyedropper: Out of bounds")
            return nil
        }

        let width = Int(bounds.width)
        let height = Int(bounds.height)

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
            print("❌ Eyedropper: Failed to create bitmap rep")
            return nil
        }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            print("❌ Eyedropper: Failed to get graphics context")
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // ⬇️ Redraw everything
        NSColor.white.setFill()
        bounds.fill()

        canvasImage?.draw(in: bounds)

        for (path, color) in drawnPaths {
            color.setStroke()
            path.stroke()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // 🟡 Sample color at pixel
        guard let color = rep.colorAt(x: x, y: y) else {
            print("❌ Eyedropper: No color at (\(x), \(y))")
            return nil
        }

        print("🎯 Eyedropper picked: \(color) at (\(x), \(y))")
        return color
    }

    func floodFill(from point: NSPoint, with fillColor: NSColor) {
        let width = Int(bounds.width)
        let height = Int(bounds.height)

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
        ) else { return }

        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        NSColor.white.setFill()
        bounds.fill()
        canvasImage?.draw(in: bounds)
        for (path, color) in drawnPaths {
            color.setStroke()
            path.stroke()
        }

        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return }

        let x = Int(point.x)
        let y = Int(bounds.height - point.y)
        guard x >= 0, x < width, y >= 0, y < height else { return }

        let offset = (y * rep.bytesPerRow) + (x * rep.samplesPerPixel)
        let startPixel = data + offset
        let targetR = startPixel[0]
        let targetG = startPixel[1]
        let targetB = startPixel[2]
        let targetA = startPixel[3]

        var rF: CGFloat = 0, gF: CGFloat = 0, bF: CGFloat = 0, aF: CGFloat = 0
        fillColor.usingColorSpace(.deviceRGB)?.getRed(&rF, green: &gF, blue: &bF, alpha: &aF)
        let newR = UInt8(rF * 255)
        let newG = UInt8(gF * 255)
        let newB = UInt8(bF * 255)
        let newA = UInt8(aF * 255)

        if targetR == newR && targetG == newG && targetB == newB && targetA == newA {
            return
        }

        var queue = [(x, y)]
        let maxPixels = 1_000_000
        var filled = 0

        while !queue.isEmpty {
            let (cx, cy) = queue.removeLast()
            if cx < 0 || cy < 0 || cx >= width || cy >= height {
                continue
            }

            let offset = (cy * rep.bytesPerRow) + (cx * rep.samplesPerPixel)
            let pixel = data + offset

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

            filled += 1
            if filled > maxPixels {
                print("⚠️ Aborting fill: exceeded max pixels")
                break
            }
        }

        if canvasImage == nil {
            canvasImage = NSImage(size: bounds.size)
            canvasImage?.lockFocus()
            NSColor.white.setFill()
            bounds.fill()
            canvasImage?.unlockFocus()
        }

        canvasImage?.lockFocus()
        rep.draw(in: bounds)
        canvasImage?.unlockFocus()

        needsDisplay = true
    }
}

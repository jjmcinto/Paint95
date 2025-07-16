import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func didPickColor(_ color: NSColor)
}

extension CanvasView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        guard let tv = textView else { return }
        commitTextView(tv)
    }
}

class CanvasView: NSView {

    weak var delegate: CanvasViewDelegate?

    var currentTool: PaintTool = .pencil
    var currentColor: NSColor = .black

    var canvasImage: NSImage? = nil
    var currentPath: NSBezierPath?
    var startPoint: NSPoint = .zero
    var endPoint: NSPoint = .zero
    var isDrawingShape: Bool = false

    var drawnPaths: [(path: NSBezierPath, color: NSColor)] = []

    // For curve tool phases
    var curvePhase = 0
    var curveStart: NSPoint = .zero
    var curveEnd: NSPoint = .zero
    var control1: NSPoint = .zero
    var control2: NSPoint = .zero
    
    //For Text Tool
    var isCreatingText = false
    var textBoxRect: NSRect = .zero
    var textView: NSTextView?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.white.setFill()
        dirtyRect.fill()

        canvasImage?.draw(in: bounds)

        for (path, color) in drawnPaths {
            color.setStroke()
            path.stroke()
        }
        
        // Optional: draw preview shape if in drawing mode
        if let previewPath = currentPath {
            currentColor.setStroke()
            previewPath.stroke()
        }

        if currentTool == .curve {
            let path = NSBezierPath()
            path.lineWidth = 2
            currentColor.set()

            switch curvePhase {
            case 0:
                if curveStart != curveEnd || curveStart != .zero {
                    path.move(to: curveStart)
                    path.line(to: curveEnd)
                    path.stroke()
                }

            case 1:
                path.move(to: curveStart)
                path.curve(to: curveEnd, controlPoint1: control1, controlPoint2: control1)
                path.stroke()

            case 2:
                path.move(to: curveStart)
                path.curve(to: curveEnd, controlPoint1: control1, controlPoint2: control2)
                path.stroke()

            default:
                break
            }
        } else if isDrawingShape {
            currentColor.set()
            let shapePath = shapePathBetween(startPoint, endPoint)
            shapePath?.lineWidth = 2
            shapePath?.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        //where applicable, end text editing
        if let tv = textView, tv.window?.firstResponder == tv {
            window?.makeFirstResponder(nil) // Triggers textDidEndEditing
            return
        }
        
        let point = convert(event.locationInWindow, from: nil)
        initializeCanvasIfNeeded()

        switch currentTool {
        case .text:
            startPoint = point
            isCreatingText = true
            
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

        case .curve:
            switch curvePhase {
            case 0:
                curveStart = point
                curveEnd = point
            case 1, 2:
                // Do nothing here — let mouseDragged preview
                break
            default:
                break
            }

        case .line, .rect, .roundRect, .ellipse:
            startPoint = point
            endPoint = point
            isDrawingShape = true

        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .text:
            if isCreatingText {
                let current = point
                textBoxRect = rectBetween(startPoint, and: current)
                needsDisplay = true
            }

        case .pencil, .brush:
            currentPath?.line(to: point)
            drawCurrentPathToCanvas()
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        case .eraser:
            currentPath?.line(to: point)
            drawCurrentPathToCanvas()
            eraseDot(at: point)
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        case .line, .rect, .roundRect, .ellipse:
            endPoint = point
            needsDisplay = true

        case .curve:
            switch curvePhase {
            case 0:
                curveEnd = point
            case 1:
                control1 = point
            case 2:
                control2 = point
            default:
                break
            }
            needsDisplay = true

        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .text:
            if isCreatingText {
                createTextView(in: textBoxRect)
                isCreatingText = false
            }

        case .pencil, .brush, .eraser:
            currentPath = nil

        case .line, .rect, .roundRect, .ellipse:
            drawShape(to: canvasImage)
            isDrawingShape = false
            needsDisplay = true

        case .curve:
            switch curvePhase {
            case 0:
                curvePhase = 1
            case 1:
                control1 = point
                curvePhase = 2
            case 2:
                control2 = point
                // Draw final curve
                let path = NSBezierPath()
                path.move(to: curveStart)
                path.curve(to: curveEnd, controlPoint1: control1, controlPoint2: control2)
                canvasImage?.lockFocus()
                currentColor.set()
                path.lineWidth = 2
                path.stroke()
                canvasImage?.unlockFocus()
                drawnPaths.append((path, currentColor))
                curvePhase = 0
                curveStart = .zero
                curveEnd = .zero
                isDrawingShape = false
                needsDisplay = true
            default:
                break
            }

        default:
            break
        }
    }
    
    func commitTextView(_ tv: NSTextView) {
        let text = tv.string
        guard !text.isEmpty else { return }
        
        initializeCanvasIfNeeded()
        canvasImage?.lockFocus()

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: tv.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: currentColor
        ]
        
        let attributed = NSAttributedString(string: text, attributes: textAttributes)
        attributed.draw(in: tv.frame)

        canvasImage?.unlockFocus()
        tv.removeFromSuperview()
        textView = nil
        needsDisplay = true
    }
    
    func createTextView(in rect: NSRect) {
        textView?.removeFromSuperview()
        
        let tv = CanvasTextView(frame: rect)
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.backgroundColor = NSColor.white
        tv.textColor = currentColor
        tv.delegate = self
        tv.isEditable = true
        tv.isSelectable = true
        tv.wantsLayer = true
        tv.layer?.borderColor = NSColor.gray.cgColor
        tv.layer?.borderWidth = 1

        addSubview(tv)
        window?.makeFirstResponder(tv)

        textView = tv
    }
    
    private func drawShape(to image: NSImage?) {
        guard let image = image else { return }
        guard let path = shapePathBetween(startPoint, endPoint) else { return }

        image.lockFocus()
        currentColor.set()
        path.lineWidth = 2
        path.stroke()
        drawnPaths.append((path.copy() as! NSBezierPath, currentColor))
        image.unlockFocus()
    }
    
    func rectBetween(_ p1: NSPoint, and p2: NSPoint) -> NSRect {
            let origin = NSPoint(x: min(p1.x, p2.x), y: min(p1.y, p2.y))
            let size = NSSize(width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
            return NSRect(origin: origin, size: size)
    }

    private func shapePathBetween(_ p1: NSPoint, _ p2: NSPoint) -> NSBezierPath? {
        let rect = rectBetween(p1, and: p2)
        let path = NSBezierPath()

        switch currentTool {
        case .line:
            path.move(to: p1)
            path.line(to: p2)

        case .rect:
            path.appendRect(rect)

        case .roundRect:
            path.appendRoundedRect(rect, xRadius: 10, yRadius: 10)

        case .ellipse:
            path.appendOval(in: rect)

        case .curve:
            // Simple quadratic Bézier approximation for now
            let controlPoint = NSPoint(x: (p1.x + p2.x) / 2, y: p1.y + 60)
            path.move(to: p1)
            path.curve(to: p2, controlPoint1: controlPoint, controlPoint2: controlPoint)

        default:
            return nil
        }

        return path
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
        
        let finalPath = path.copy() as! NSBezierPath
        var strokeColor: NSColor
        var lineWidth: CGFloat

        switch currentTool {
        case .pencil:
            strokeColor = currentColor
            lineWidth = 1

        case .brush:
            strokeColor = currentColor
            lineWidth = 5

        case .eraser:
            path.lineCapStyle = .butt
            path.lineJoinStyle = .miter
            strokeColor = .white
            lineWidth = 15

        default:
            return  // don't accidentally fall through
        }

        finalPath.lineWidth = lineWidth
        drawnPaths.append((path: finalPath, color: strokeColor))
        currentPath = nil
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

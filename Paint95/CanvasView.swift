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

extension Notification.Name {
    static let toolChanged = Notification.Name("PaintToolChangedNotification")
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
    var colorFromSelectionWindow: Bool = false
    
    // Size selection
    var toolSize: CGFloat = 1.0

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
    
    //For Selection Tool
    var selectionRect: NSRect?
    var selectedImage: NSImage?
    var isPasting: Bool = false
    var pasteOrigin: NSPoint = .zero
    var pastedImage: NSImage?
    var pastedImageOrigin: NSPoint?
    var isPastingImage: Bool = false
    var isPastingActive: Bool = false
    var pasteDragStartPoint: NSPoint?
    var pasteDragOffset: NSPoint?
    var pasteImageStartOrigin: NSPoint?
    var isDraggingPastedImage: Bool = false
    var selectedImageOrigin: NSPoint? = nil
    var hasMovedSelection: Bool = false
    var isCutSelection: Bool = false
    var isDraggingSelection = false
    var selectionDragStartPoint: NSPoint?
    var selectionImageStartOrigin: NSPoint?
    
    //canvas re-size
    enum ResizeHandle: Int {
        case bottomLeft = 0, bottomCenter, bottomRight
        case middleLeft, middleRight
        case topLeft, topCenter, topRight
    }
    let handleSize: CGFloat = 5
    var activeResizeHandle: ResizeHandle? = nil
    var isResizingCanvas = false
    var dragStartPoint: NSPoint = .zero
    var initialCanvasRect: NSRect = .zero
    var canvasRect = NSRect(x: 0, y: 0, width: 600, height: 400)
    var handlePositions: [NSPoint] {
        let offset = handleSize / 2
        return [
            NSPoint(x: canvasRect.minX - offset, y: canvasRect.minY - offset), // bottom-left
            NSPoint(x: canvasRect.midX - offset, y: canvasRect.minY - offset), // bottom-center
            NSPoint(x: canvasRect.maxX, y: canvasRect.minY - offset),          // bottom-right
            NSPoint(x: canvasRect.minX - offset, y: canvasRect.midY - offset), // middle-left
            NSPoint(x: canvasRect.maxX, y: canvasRect.midY - offset),          // middle-right
            NSPoint(x: canvasRect.minX - offset, y: canvasRect.maxY),          // top-left
            NSPoint(x: canvasRect.midX - offset, y: canvasRect.maxY),          // top-center
            NSPoint(x: canvasRect.maxX, y: canvasRect.maxY)                    // top-right
        ]
    }
    
    //selection re-size
    enum SelectionHandle: Int {
        case topLeft = 0, topCenter, topRight, middleLeft, middleRight, bottomLeft, bottomCenter, bottomRight
    }
    var activeSelectionHandle: SelectionHandle? = nil
    var isResizingSelection = false
    var resizeStartPoint: NSPoint = .zero
    var originalSelectionRect: NSRect = .zero
    var originalSelectedImage: NSImage? = nil
    
    //Zoom
    var isZoomed: Bool = false
    var zoomRect: NSRect = .zero
    var zoomPreviewRect: NSRect = .zero
    var mousePosition: NSPoint = .zero
    
    //spray paint
    var sprayTimer: Timer?
    let sprayRadius: CGFloat = 10
    let sprayDensity: Int = 30
    var currentSprayPoint: NSPoint = .zero
    
    // Undo/Redo
    private var undoStack: [NSImage] = []
    private var redoStack: [NSImage] = []
    private let maxUndoSteps = 5
    private var cancelCurvePreview = false
    
    func saveCanvasToDefaultLocation() {
        guard let canvasImage = canvasImage else {
            print("No canvas image to save.")
            return
        }

        // Create file path
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Jeffrey/projects/PaintProgram/out.jpg")

        // Convert NSImage to JPEG data
        guard let tiffData = canvasImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            print("Failed to generate JPEG data.")
            return
        }

        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpegData.write(to: path)
            print("Canvas saved to \(path.path)")
        } catch {
            print("Save failed: \(error)")
        }
    }
    
    func colorSelectedFromPalette(_ color: NSColor) {
        SharedColor.currentColor = color
        SharedColor.source = .palette

        // Approximate RGB from NSColor
        if let rgbColor = color.usingColorSpace(.deviceRGB) {
            SharedColor.rgb = [
                Double(rgbColor.redComponent * 255.0),
                Double(rgbColor.greenComponent * 255.0),
                Double(rgbColor.blueComponent * 255.0)
            ]
        }

        self.currentColor = color
        needsDisplay = true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(colorPicked(_:)), name: .colorPicked, object: nil)
        let trackingArea = NSTrackingArea(rect: self.bounds,
                                          options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        self.addTrackingArea(trackingArea)
    }

    @objc func colorPicked(_ notification: Notification) {
        if let newColor = notification.object as? NSColor {
            currentColor = newColor
            colorFromSelectionWindow = true // Track source
            needsDisplay = true
        }
    }
    
    @objc public func handleDeleteKey() {
        if isPastingActive {
            pastedImage = nil
            pastedImageOrigin = nil
            isPastingImage = false
            isPastingActive = false
            needsDisplay = true
        } else if let rect = selectionRect {
            clearCanvasRegion(rect: rect)
            selectionRect = nil
            selectedImage = nil
            needsDisplay = true
        }
    }
    
    func showColorSelectionWindow() {
        var rgbColor: [Double] = [0,0,0]
        
        if colorFromSelectionWindow {
            rgbColor = AppColorState.shared.rgb
        } else {
            // Approximate RGB from NSColor
            if let rgbColor = currentColor.usingColorSpace(.deviceRGB) {
                SharedColor.rgb = [
                    Double(rgbColor.redComponent * 255.0),
                    Double(rgbColor.greenComponent * 255.0),
                    Double(rgbColor.blueComponent * 255.0)
                ]
            }
        }
        
        let controller = ColorSelectionWindowController(initialRGB: rgbColor, onColorSelected: { [weak self] newColor in
            self?.currentColor = newColor
            NotificationCenter.default.post(name: .colorPicked, object: newColor)
        })
        controller.showWindow(nil)
    }
    
    func setCurrentColor(_ color: NSColor) {
        currentColor = color
        needsDisplay = true
    }
    
    func clearCanvasRegion(rect: NSRect, lockFocus: Bool = true) {
        if lockFocus { canvasImage?.lockFocus() }
        NSColor.white.setFill()
        rect.fill()
        if lockFocus { canvasImage?.unlockFocus() }
        
        // Remove intersecting paths
        drawnPaths.removeAll { (path, _) in
            return path.bounds.intersects(rect)
        }
    }
    
    override var canBecomeKeyView: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        clearCanvasRegion(rect: dirtyRect, lockFocus: false)
        
        // === Canvas image drawing ===
        if isResizingCanvas {
            let originalRect = NSRect(origin: .zero, size: canvasImage?.size ?? .zero)
            canvasImage?.draw(in: originalRect)

            NSColor.red.setStroke()
            let dashPattern: [CGFloat] = [5.0, 3.0]
            let path = NSBezierPath(rect: canvasRect)
            path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            path.stroke()
        } else if isZoomed {
            guard let image = canvasImage else { return }
            let magnified = NSImage(size: canvasRect.size)
            magnified.lockFocus()
            image.draw(in: canvasRect, from: zoomRect, operation: .copy, fraction: 1.0)
            magnified.unlockFocus()
            magnified.draw(in: canvasRect)
        } else {
            canvasImage?.draw(in: canvasRect)
            if currentTool == .zoom {
                NSColor.black.setStroke()
                let path = NSBezierPath(rect: zoomPreviewRect)
                path.lineWidth = 1
                path.stroke()  // now solid line, no dashes
            }
        }

        // === Selected image preview ===
        if let image = selectedImage, let io = selectedImageOrigin {
            let selectionFrame = NSRect(origin: io, size: image.size)
            let visiblePortion = selectionFrame.intersection(canvasRect)
            if !visiblePortion.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                let clipPath = NSBezierPath(rect: canvasRect)
                clipPath.addClip()
                image.draw(at: io, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
            }

            NSColor.black.setStroke()
            let dashPattern: [CGFloat] = [5.0, 3.0]
            let path = NSBezierPath(rect: selectionFrame.intersection(canvasRect))
            path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            path.lineWidth = 1
            path.stroke()

            let handleSize: CGFloat = 6
            let handles = [
                NSPoint(x: selectionFrame.minX - handleSize/2, y: selectionFrame.minY - handleSize/2),
                NSPoint(x: selectionFrame.midX - handleSize/2, y: selectionFrame.minY - handleSize/2),
                NSPoint(x: selectionFrame.maxX - handleSize/2, y: selectionFrame.minY - handleSize/2),
                NSPoint(x: selectionFrame.minX - handleSize/2, y: selectionFrame.midY - handleSize/2),
                NSPoint(x: selectionFrame.maxX - handleSize/2, y: selectionFrame.midY - handleSize/2),
                NSPoint(x: selectionFrame.minX - handleSize/2, y: selectionFrame.maxY - handleSize/2),
                NSPoint(x: selectionFrame.midX - handleSize/2, y: selectionFrame.maxY - handleSize/2),
                NSPoint(x: selectionFrame.maxX - handleSize/2, y: selectionFrame.maxY - handleSize/2)
            ]
            NSColor.systemBlue.setFill()
            for p in handles {
                NSBezierPath(rect: NSRect(x: p.x, y: p.y, width: handleSize, height: handleSize)).fill()
            }
        } else if let rect = selectionRect {
            NSColor.black.setStroke()
            let dashPattern: [CGFloat] = [5.0, 3.0]
            let path = NSBezierPath(rect: rect)
            path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            path.lineWidth = 1
            path.stroke()
        }

        if let previewPath = currentPath {
            currentColor.setStroke()
            previewPath.stroke()
        }

        // === Curve preview (always show active curve stage) ===
        if currentTool == .curve && !cancelCurvePreview {
            var start = curveStart
            var end = curveEnd
            var c1 = control1
            var c2 = control2

            if isZoomed {
                let scaleX = canvasRect.width / zoomRect.width
                let scaleY = canvasRect.height / zoomRect.height
                let originX = zoomRect.origin.x
                let originY = zoomRect.origin.y

                func zoomed(_ p: NSPoint) -> NSPoint {
                    return NSPoint(x: (p.x - originX) * scaleX,
                                   y: (p.y - originY) * scaleY)
                }

                start = zoomed(start)
                end = zoomed(end)
                c1 = zoomed(c1)
                c2 = zoomed(c2)
            }

            let path = NSBezierPath()
            path.lineWidth = toolSize
            currentColor.set()

            switch curvePhase {
            case 0:
                if start != end {
                    path.move(to: start)
                    path.line(to: end)
                    path.stroke()
                }
            case 1:
                path.move(to: start)
                path.curve(to: end, controlPoint1: c1, controlPoint2: c1)
                path.stroke()
            case 2:
                path.move(to: start)
                path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                path.stroke()
            default:
                break
            }
            cancelCurvePreview = false
        }
        else if isDrawingShape {
            currentColor.set()
            var start = startPoint
            var end = endPoint

            if isZoomed {
                let scaleX = canvasRect.width / zoomRect.width
                let scaleY = canvasRect.height / zoomRect.height
                start.x = (start.x - zoomRect.origin.x) * scaleX
                start.y = (start.y - zoomRect.origin.y) * scaleY
                end.x   = (end.x   - zoomRect.origin.x) * scaleX
                end.y   = (end.y   - zoomRect.origin.y) * scaleY
            }

            if let shapePath = shapePathBetween(start, end) {
                shapePath.lineWidth = toolSize
                shapePath.stroke()
            }
        }
        else if isCreatingText {
            NSColor.gray.setStroke()
            let path = NSBezierPath(rect: textBoxRect)
            let dashPattern: [CGFloat] = [4, 2]
            path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            path.lineWidth = 1
            path.stroke()
        }

        NSColor.black.setStroke()
        NSBezierPath(rect: canvasRect).stroke()

        NSColor.systemBlue.setFill()
        for position in handlePositions {
            let rect = NSRect(x: position.x, y: position.y, width: handleSize, height: handleSize)
            NSBezierPath(rect: rect).fill()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let tv = textView {
            if tv.window?.firstResponder == tv {
                commitTextView(tv)
                return
            } else {
                tv.removeFromSuperview()
                textView = nil
            }
        }
        let point = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))

        // === Selection handle detection (resize) ===
        if let rect = selectionRect ?? (selectedImage != nil ? NSRect(origin: selectedImageOrigin ?? .zero, size: selectedImage!.size) : nil) {
            for (i, handle) in selectionHandlePositions(rect: rect).enumerated() {
                if handle.contains(point) {
                    saveUndoState()  // <-- checkpoint before selection resize
                    activeResizeHandle = ResizeHandle(rawValue: i)
                    isResizingSelection = true
                    resizeStartPoint = point
                    originalSelectionRect = rect
                    originalSelectedImage = selectedImage
                    return
                }
            }
        }

        // === Canvas handle detection ===
        for (i, pos) in handlePositions.enumerated() {
            let handleRect = NSRect(x: pos.x, y: pos.y, width: handleSize, height: handleSize)
            if handleRect.contains(point) {
                saveUndoState()  // <-- checkpoint before canvas resize
                activeResizeHandle = ResizeHandle(rawValue: i)
                isResizingCanvas = true
                dragStartPoint = point
                initialCanvasRect = canvasRect
                return
            }
        }
        
        // If we are in paste mode and the click is outside the active selection, commit the paste
        if isPastingImage,
           let img = selectedImage, let io = selectedImageOrigin {
            let activeRect = NSRect(origin: io, size: img.size)
            if !activeRect.contains(point) {
                // Reuse the selection commit to draw the overlay into the canvas
                commitSelection()
                // Clear paste-mode flags
                isPastingImage = false
                isPastingActive = false
                pastedImage = nil
                pastedImageOrigin = nil
                // Do NOT return; allow this same click to proceed (e.g., start a new selection)
            }
        }
        
        /*
        // === Selection outside click ===
        if let image = selectedImage, let io = selectedImageOrigin {
            let selectionFrame = NSRect(origin: io, size: image.size)
            if !selectionFrame.contains(point) {
                commitSelection()
                return
            }
        }
        */

        initializeCanvasIfNeeded()

        switch currentTool {
        case .select:
            if let image = selectedImage, let io = selectedImageOrigin {
                let rect = NSRect(origin: io, size: image.size)
                if rect.contains(point) {
                    saveUndoState()  // <-- checkpoint before selection move
                    isDraggingSelection = true
                    selectionDragStartPoint = point
                    selectionImageStartOrigin = selectedImageOrigin
                    if !isPastingImage { // do NOT clear during uncommitted paste move
                        clearCanvasRegion(rect: rect)
                    }
                }
            } else if !isPastingImage {
                startPoint = point
                selectionRect = nil
                selectedImage = nil
                self.window?.makeFirstResponder(self)
            }

        case .spray:
            currentSprayPoint = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
            startSpray()

        case .text:
            startPoint = point
            isCreatingText = true

        case .eyeDropper:
            if let picked = pickColor(at: point) {
                currentColor = picked
                NotificationCenter.default.post(name: .colorPicked, object: picked)
                colorFromSelectionWindow = false
            }

        case .pencil, .brush, .eraser:
            saveUndoState()  // <-- checkpoint at stroke start
            startPoint = point
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        case .fill:
            saveUndoState()
            floodFill(from: point, with: currentColor)

        case .curve:
            switch curvePhase {
            case 0:
                saveUndoState()  // <-- checkpoint at start of curve
                curveStart = point
                curveEnd = point
            default:
                break
            }

        case .line, .rect, .roundRect, .ellipse:
            saveUndoState()  // <-- checkpoint at start of shape
            startPoint = point
            endPoint = point
            isDrawingShape = true

        case .zoom:
            if isZoomed {
                isZoomed = false
                zoomRect = .zero
                needsDisplay = true
            } else {
                let zoomSize: CGFloat = 100
                let point = convert(event.locationInWindow, from: nil)
                zoomRect = NSRect(x: point.x - zoomSize/2, y: point.y - zoomSize/2,
                                  width: zoomSize, height: zoomSize)
                isZoomed = true
                needsDisplay = true
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
        let shiftPressed = event.modifierFlags.contains(.shift)
        
        // === Selection resizing (reuse for pasted content; non-destructive while pasting) ===
        if isResizingSelection, let handle = activeResizeHandle {
            let dx = point.x - resizeStartPoint.x
            let dy = point.y - resizeStartPoint.y
            var newRect = originalSelectionRect

            switch handle {
            case .topLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
                newRect.size.height += dy
            case .topCenter:
                newRect.size.height += dy
            case .topRight:
                newRect.size.width += dx
                newRect.size.height += dy
            case .middleLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
            case .middleRight:
                newRect.size.width += dx
            case .bottomLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .bottomCenter:
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .bottomRight:
                newRect.size.width += dx
                newRect.origin.y += dy
                newRect.size.height -= dy
            }

            if shiftPressed {
                let aspect = originalSelectionRect.width / max(originalSelectionRect.height, 1)
                if handle == .topLeft || handle == .topRight || handle == .bottomLeft || handle == .bottomRight {
                    let widthSign: CGFloat = newRect.width >= 0 ? 1 : -1
                    let heightSign: CGFloat = newRect.height >= 0 ? 1 : -1
                    if abs(newRect.width) > abs(newRect.height * aspect) {
                        newRect.size.height = abs(newRect.width) / aspect * heightSign
                    } else {
                        newRect.size.width = abs(newRect.height * aspect) * widthSign
                    }
                }
            }

            // ⚠️ Non-destructive while pasting: just update the preview buffers
            if let image = originalSelectedImage {
                // Create a scaled copy for the preview
                let scaled = NSImage(size: newRect.size)
                scaled.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: newRect.size),
                           from: NSRect(origin: .zero, size: image.size),
                           operation: .copy,
                           fraction: 1.0)
                scaled.unlockFocus()

                selectedImage = scaled
                selectedImageOrigin = newRect.origin
                selectionRect = newRect
            }

            needsDisplay = true
            return
        }


        // === Canvas resize ===
        if isResizingCanvas, let handle = activeResizeHandle {
            let dx = point.x - dragStartPoint.x
            let dy = point.y - dragStartPoint.y
            var newRect = initialCanvasRect

            switch handle {
            case .bottomLeft:
                newRect.origin.x += dx
                newRect.origin.y += dy
                newRect.size.width -= dx
                newRect.size.height -= dy
            case .bottomCenter:
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .bottomRight:
                newRect.origin.y += dy
                newRect.size.height -= dy
                newRect.size.width += dx
            case .middleLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
            case .middleRight:
                newRect.size.width += dx
            case .topLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
                newRect.size.height += dy
            case .topCenter:
                newRect.size.height += dy
            case .topRight:
                newRect.size.width += dx
                newRect.size.height += dy
            }

            if newRect.width < 50 { newRect.size.width = 50 }
            if newRect.height < 50 { newRect.size.height = 50 }

            canvasRect = newRect
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            return
        }
        
        // === Dragging selection ===
        if isDraggingSelection,
           let startPoint = selectionDragStartPoint,
           let imageOrigin = selectionImageStartOrigin,
           let selectedImage = selectedImage {

            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let newOrigin = NSPoint(x: imageOrigin.x + dx, y: imageOrigin.y + dy)

            selectedImageOrigin = newOrigin
            selectionRect = NSRect(origin: newOrigin, size: selectedImage.size)
            needsDisplay = true
            return
        }

        // === Tool actions ===
        switch currentTool {
        case .select:
            if !isPastingImage {
                endPoint = point
                selectionRect = rectBetween(startPoint, and: endPoint)
                needsDisplay = true
            }
        case .spray:
            currentSprayPoint = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
        case .text:
            if isCreatingText {
                textBoxRect = rectBetween(startPoint, and: point)
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
            // === Shift constraints for shapes ===
            if shiftPressed {
                let dx = endPoint.x - startPoint.x
                let dy = endPoint.y - startPoint.y
                switch currentTool {
                case .line:
                    // Constrain to 45-degree increments
                    let angle = atan2(dy, dx)
                    let snap = round(angle / (.pi / 4)) * (.pi / 4)
                    let length = hypot(dx, dy)
                    endPoint = NSPoint(x: startPoint.x + cos(snap) * length,
                                       y: startPoint.y + sin(snap) * length)
                case .rect, .roundRect, .ellipse:
                    // Force square/circle
                    let size = max(abs(dx), abs(dy))
                    endPoint.x = startPoint.x + (dx >= 0 ? size : -size)
                    endPoint.y = startPoint.y + (dy >= 0 ? size : -size)
                default: break
                }
            }
            needsDisplay = true
        case .curve:
            switch curvePhase {
            case 0: curveEnd = point
            case 1: control1 = point
            case 2: control2 = point
            default: break
            }
            needsDisplay = true
        default: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        
        if isResizingCanvas {
            isResizingCanvas = false
            activeResizeHandle = nil
            cropCanvasImageToCanvasRect()
            needsDisplay = true
            return
        }

        if isResizingSelection {
            isResizingSelection = false
            activeResizeHandle = nil
            needsDisplay = true
            return
        }

        if isDraggingPastedImage {
            isDraggingPastedImage = false
            return
        }

        if isDraggingSelection {
            isDraggingSelection = false
            selectionDragStartPoint = nil
            selectionImageStartOrigin = nil
            return
        }

        let point = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
        let shiftPressed = event.modifierFlags.contains(.shift)

        if let image = selectedImage, let io = selectedImageOrigin {
            let rect = NSRect(origin: io, size: image.size)
            if !rect.contains(point) {
                commitSelection()
                return
            }
        } else if isResizingCanvas {
            isResizingCanvas = false
            activeResizeHandle = nil
            needsDisplay = true
            return
        }

        // === Commit pasted content only if mouse up outside the selection frame ===
        if isPastingImage, let image = selectedImage, let io = selectedImageOrigin {
            let frame = NSRect(origin: io, size: image.size)
            let upPoint = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
            if !frame.contains(upPoint) {
                // Reuse selection commit for paste, then exit paste mode
                commitSelection()
                isPastingImage = false
                isPastingActive = false
                needsDisplay = true
                return
            }
            // If mouse up inside, keep editing (no commit)
        }
        endPoint = point

        switch currentTool {
        case .select:
            guard let rect = selectionRect else { return }
            let image = NSImage(size: rect.size)
            image.lockFocus()
            canvasImage?.draw(at: .zero, from: rect, operation: .copy, fraction: 1.0)
            image.unlockFocus()
            selectedImage = image
            selectedImageOrigin = rect.origin
            window?.invalidateCursorRects(for: self)
            needsDisplay = true

        case .spray:
            stopSpray()

        case .text:
            if isCreatingText && textBoxRect != .zero {
                createTextView(in: textBoxRect)
                textBoxRect = .zero
                isCreatingText = false
            }

        case .pencil:
            if pointsAreEqual(startPoint, endPoint) {
                initializeCanvasIfNeeded()
                canvasImage?.lockFocus()
                currentColor.set()
                let dotRect = NSRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1)
                dotRect.fill()
                canvasImage?.unlockFocus()
                needsDisplay = true
            }
            currentPath = nil

        case .brush:
            if pointsAreEqual(startPoint, endPoint) {
                initializeCanvasIfNeeded()
                canvasImage?.lockFocus()
                currentColor.set()
                let brushSize: CGFloat = 5
                let dotRect = NSRect(x: startPoint.x - brushSize/2,
                                     y: startPoint.y - brushSize/2,
                                     width: brushSize, height: brushSize)
                NSBezierPath(ovalIn: dotRect).fill()
                canvasImage?.unlockFocus()
                needsDisplay = true
            }
            currentPath = nil

        case .eraser:
            if pointsAreEqual(startPoint, endPoint) {
                eraseDot(at: startPoint, radius: 7.5)
                needsDisplay = true
            }
            currentPath = nil

        case .line, .rect, .roundRect, .ellipse:
            var finalEnd = endPoint

            // === Shift constraints at commit time ===
            if shiftPressed {
                let dx = finalEnd.x - startPoint.x
                let dy = finalEnd.y - startPoint.y
                switch currentTool {
                case .line:
                    let angle = atan2(dy, dx)
                    let snap = round(angle / (.pi / 4)) * (.pi / 4)
                    let length = hypot(dx, dy)
                    finalEnd = NSPoint(x: startPoint.x + cos(snap) * length,
                                       y: startPoint.y + sin(snap) * length)
                case .rect, .roundRect, .ellipse:
                    let size = max(abs(dx), abs(dy))
                    finalEnd.x = startPoint.x + (dx >= 0 ? size : -size)
                    finalEnd.y = startPoint.y + (dy >= 0 ? size : -size)
                default: break
                }
            }

            if pointsAreEqual(startPoint, finalEnd) {
                initializeCanvasIfNeeded()
                canvasImage?.lockFocus()
                currentColor.set()
                let dotRect = NSRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1)
                dotRect.fill()
                canvasImage?.unlockFocus()
            } else {
                endPoint = finalEnd // use corrected endPoint
                drawShape(to: canvasImage)
            }
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
                let path = NSBezierPath()
                path.move(to: curveStart)
                path.curve(to: curveEnd, controlPoint1: control1, controlPoint2: control2)
                path.lineWidth = toolSize
                let translatedPath = path.copy() as! NSBezierPath
                let transform = AffineTransform(translationByX: -canvasRect.origin.x, byY: -canvasRect.origin.y)
                translatedPath.transform(using: transform)
                canvasImage?.lockFocus()
                currentColor.set()
                translatedPath.stroke()
                canvasImage?.unlockFocus()
                drawnPaths.append((path: translatedPath.copy() as! NSBezierPath, color: currentColor))
                curvePhase = 0
                curveStart = .zero
                curveEnd = .zero
                control1 = .zero
                control2 = .zero
                isDrawingShape = false
                needsDisplay = true
            default:
                break
            }
        default:
            break
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)

        let point = convert(event.locationInWindow, from: nil)

        if currentTool == .zoom {
            let zoomSize: CGFloat = 100
            zoomPreviewRect = NSRect(
                x: point.x - zoomSize / 2,
                y: point.y - zoomSize / 2,
                width: zoomSize,
                height: zoomSize
            )
            needsDisplay = true
        }

        window?.invalidateCursorRects(for: self)
    }
    
    override func keyDown(with event: NSEvent) {
        guard event.type == .keyDown else { return }
        if event.modifierFlags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "s":
                    saveCanvasToDefaultLocation()
                default:
                    break
                }
            }
        }
        else if isPastingActive, let characters = event.charactersIgnoringModifiers {
            if characters == "\r" || characters == "\n" {
                // Enter or Return pressed
                commitPastedImage()
            }
        } else {
            let key = event.keyCode

            // Move selected image with arrow keys
            if let image = selectedImage, let io = selectedImageOrigin {
                if isCutSelection {
                    // Clear original selection area from canvas
                    let clearRect = NSRect(origin: io, size: image.size)
                    canvasImage?.lockFocus()
                    NSColor.white.setFill()
                    clearRect.fill()
                    canvasImage?.unlockFocus()
                }

                // Shift the selection origin
                var origin = io
                switch key {
                case 123: origin.x -= 1 // ←
                case 124: origin.x += 1 // →
                case 125: origin.y -= 1 // ↓
                case 126: origin.y += 1 // ↑
                case 36:  commitSelection(); return
                case 51:  deleteSelectionOrPastedImage(); return
                default:
                    super.keyDown(with: event)
                    return
                }

                selectedImageOrigin = origin
                needsDisplay = true
                return
            }

            super.keyDown(with: event)
        }
    }
    
    func cutSelection() {
        guard let rect = selectionRect else { return }

        // Copy to clipboard
        let image = NSImage(size: rect.size)
        image.lockFocus()
        canvasImage?.draw(at: .zero, from: rect, operation: .copy, fraction: 1.0)
        image.unlockFocus()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        // Delete the content (this clears canvas + drawn paths)
        deleteSelectionOrPastedImage()

        // Clear selection state
        selectionRect = nil
        selectedImage = nil
        selectedImageOrigin = nil

        // Redraw now — without selected preview
        needsDisplay = true
    }

    func copySelection() {
        guard let image = selectedImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
        isCutSelection = false
    }

    func pasteImage() {
        let pasteboard = NSPasteboard.general

        // If something is already being pasted, commit it first
        if isPastingImage {
            commitPastedImage()
            isPastingImage = false
            pastedImage = nil
            pastedImageOrigin = nil
        }
        
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = images.first {

            // Clear any old selection state
            selectionRect = nil
            selectedImage = nil
            selectedImageOrigin = nil

            // Start Paste Mode (overlay)
            pastedImage = img
            let origin = NSPoint(x: 100, y: 100)
            pastedImageOrigin = origin
            isPastingImage = true
            isPastingActive = true
            hasMovedSelection = false

            // Make the pasted content the active "selection"
            selectedImage = img
            selectedImageOrigin = origin
            selectionRect = NSRect(origin: origin, size: img.size)

            // Ensure the selection tool is active so move/resize works
            currentTool = .select
            NotificationCenter.default.post(name: .toolChanged, object: PaintTool.select)

            self.window?.makeFirstResponder(self)
            needsDisplay = true
        }
    }

    func commitSelection() {
        saveUndoState()
        guard let image = selectedImage, let origin = selectedImageOrigin else { return }
        let imageRect = NSRect(origin: origin, size: image.size)
        let intersection = imageRect.intersection(canvasRect)

        guard !intersection.isEmpty else {
            // Entire selection is outside the canvas — discard it
            selectedImage = nil
            selectedImageOrigin = nil
            selectionRect = nil
            needsDisplay = true
            return
        }

        // Calculate the portion of the image that intersects canvasRect
        let drawOriginInImage = NSPoint(x: intersection.origin.x - origin.x,
                                        y: intersection.origin.y - origin.y)
        let drawRectInImage = NSRect(origin: drawOriginInImage, size: intersection.size)

        initializeCanvasIfNeeded()
        canvasImage?.lockFocus()

        image.draw(at: intersection.origin,
                   from: drawRectInImage,
                   operation: .sourceOver,
                   fraction: 1.0)

        canvasImage?.unlockFocus()

        // Clear selection state
        selectedImage = nil
        selectedImageOrigin = nil
        selectionRect = nil
        needsDisplay = true
    }

    func commitPastedImage() {
        // If we unified paste → selection, just reuse selection commit
        if selectedImage != nil, selectedImageOrigin != nil {
            commitSelection()
        }
        // Clear paste flags regardless
        pastedImage = nil
        pastedImageOrigin = nil
        pasteDragOffset = nil
        pasteImageStartOrigin = nil
        pasteDragStartPoint = nil
        isPastingImage = false
        isPastingActive = false
        isDraggingPastedImage = false
        needsDisplay = true
    }
    
    func selectionHandlePositions(rect: NSRect) -> [NSRect] {
        let size: CGFloat = 6
        let half = size / 2
        return [
            NSRect(x: rect.minX - half, y: rect.minY - half, width: size, height: size), // bottom-left
            NSRect(x: rect.midX - half, y: rect.minY - half, width: size, height: size), // bottom-center
            NSRect(x: rect.maxX - half, y: rect.minY - half, width: size, height: size),  // bottom-right
            NSRect(x: rect.minX - half, y: rect.midY - half, width: size, height: size), // middle-left
            NSRect(x: rect.maxX - half, y: rect.midY - half, width: size, height: size), // middle-right
            NSRect(x: rect.minX - half, y: rect.maxY - half, width: size, height: size), // top-left
            NSRect(x: rect.midX - half, y: rect.maxY - half, width: size, height: size), // top-center
            NSRect(x: rect.maxX - half, y: rect.maxY - half, width: size, height: size) // top-right
        ]
    }
    
    func commitTextView(_ tv: NSTextView) {
        let text = tv.string
        guard !text.isEmpty else { return }
        
        // Make undo checkpoint for adding text
        saveUndoState()

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
    
    // Save current state before modifying canvasImage
    private func saveUndoState() {
        guard let currentImage = canvasImage else { return }
        if undoStack.count >= maxUndoSteps {
            undoStack.removeFirst() // keep last 5 steps
        }
        undoStack.append(currentImage.copy() as! NSImage)
        redoStack.removeAll() // clear redo on new change
    }
    
    @objc func undo() {
        guard let lastImage = undoStack.popLast() else { return }
        if let currentImage = canvasImage {
            redoStack.append(currentImage.copy() as! NSImage)
        }
        canvasImage = lastImage.copy() as? NSImage
        
        // Reset curve state after undo
        curvePhase = 0
        curveStart = .zero
        curveEnd = .zero
        control1 = .zero
        control2 = .zero
        cancelCurvePreview = false

        needsDisplay = true
    }
    
    @objc func redo() {
        guard let nextImage = redoStack.popLast() else { return }
        if let currentImage = canvasImage {
            undoStack.append(currentImage.copy() as! NSImage)
        }
        canvasImage = nextImage.copy() as? NSImage
        
        // Reset curve state after redo
        curvePhase = 0
        curveStart = .zero
        curveEnd = .zero
        control1 = .zero
        control2 = .zero
        cancelCurvePreview = false

        needsDisplay = true
    }
    
    private func cropCanvasImageToCanvasRect() {
        guard let image = canvasImage else { return }

        // Create a new image the same size as the new canvasRect
        let newSize = canvasRect.size
        let newImage = NSImage(size: newSize)

        // Source origin is relative to the original image (always top-left origin)
        let sourceRect = NSRect(origin: canvasRect.origin, size: newSize)

        // Destination rect always starts at (0, 0)
        let destRect = NSRect(origin: .zero, size: newSize)

        newImage.lockFocus()

        image.draw(
            in: destRect,
            from: sourceRect,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )

        newImage.unlockFocus()

        // Update the canvas image and reset origin to zero
        canvasImage = newImage
        canvasRect.origin = .zero
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
        saveUndoState()

        let path = shapePathBetween(startPoint, endPoint)
        path?.lineWidth = toolSize

        let transformedPath = path?.copy() as! NSBezierPath
        let transform = AffineTransform(translationByX: -canvasRect.origin.x, byY: -canvasRect.origin.y)
        transformedPath.transform(using: transform)

        image.lockFocus()
        currentColor.setStroke()
        transformedPath.stroke()
        image.unlockFocus()

        drawnPaths.append((path: transformedPath.copy() as! NSBezierPath, color: currentColor))
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
        
        // Prepare a translated copy of the path
        let translatedPath = path.copy() as! NSBezierPath
        let transform = AffineTransform(translationByX: -canvasRect.origin.x, byY: -canvasRect.origin.y)
        translatedPath.transform(using: transform)

        translatedPath.lineCapStyle = .butt
        translatedPath.lineJoinStyle = .miter
        
        var strokeColor: NSColor
        var lineWidth: CGFloat

        switch currentTool {
        case .pencil:
            strokeColor = currentColor
            lineWidth = 1
        case .brush:
            strokeColor = currentColor
            lineWidth = toolSize
        case .eraser:
            strokeColor = .white
            lineWidth = toolSize * 3
        default:
            return
        }

        translatedPath.lineWidth = lineWidth

        // Draw to the canvas image
        canvasImage?.lockFocus()
        strokeColor.set()
        translatedPath.stroke()
        canvasImage?.unlockFocus()

        drawnPaths.append((path: translatedPath.copy() as! NSBezierPath, color: strokeColor))

        currentPath = nil
        needsDisplay = true
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        
        // Canvas resize handles
        for (i, position) in handlePositions.enumerated() {
            let handleRect = NSRect(x: position.x, y: position.y, width: handleSize, height: handleSize)
            let cursor = cursorForHandle(index: i)
            addCursorRect(handleRect, cursor: cursor)
        }
        
        // Selection resize handles (if selection or pasted image exists)
        if let selectionFrame = (selectedImage != nil
            ? NSRect(origin: selectedImageOrigin ?? .zero, size: selectedImage!.size)
            : selectionRect) {

            let selectionHandles = selectionHandlePositions(rect: selectionFrame)
            for (i, handleRect) in selectionHandles.enumerated() {
                let cursor = cursorForHandle(index: i)
                addCursorRect(handleRect, cursor: cursor)
            }
        }
    }
    
    private func cursorForHandle(index: Int) -> NSCursor {
        switch index {
        case 1, 6:
            return .resizeUpDown
        case 3, 4:
            return .resizeLeftRight
        case 5, 2:
            return NSCursor(image: NSImage(byReferencingFile: "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northWestSouthEastResizeCursor.png")!, hotSpot: NSPoint(x: 8, y: 8))
        case 7, 0:
            return NSCursor(image: NSImage(byReferencingFile: "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northEastSouthWestResizeCursor.png")!, hotSpot: NSPoint(x: 8, y: 8))
        default:
            return .arrow // fallback for corners
        }
    }
    
    func convertZoomedPointToCanvas(_ point: NSPoint) -> NSPoint {
        guard isZoomed else { return point }

        let scaleX = zoomRect.width / canvasRect.width
        let scaleY = zoomRect.height / canvasRect.height
        
        // Convert from full-size display to original canvas coordinates
        let adjustedX = zoomRect.origin.x + point.x * scaleX
        let adjustedY = zoomRect.origin.y + point.y * scaleY

        return NSPoint(x: adjustedX, y: adjustedY)
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resetCursorRects()
    }
    
    private func eraseDot(at point: NSPoint, radius: CGFloat = 7.5) {
        saveUndoState()
        initializeCanvasIfNeeded()
        canvasImage?.lockFocus()
        NSColor.white.set()
        let rect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        NSBezierPath(rect: rect).fill()
        canvasImage?.unlockFocus()
    }
    
    func convertZoomedPoint(_ point: NSPoint) -> NSPoint {
        // zoomRect maps to full canvasRect
        let scaleX = canvasRect.width / zoomRect.width
        let scaleY = canvasRect.height / zoomRect.height
        let translatedX = zoomRect.origin.x + point.x / scaleX
        let translatedY = zoomRect.origin.y + point.y / scaleY
        return NSPoint(x: translatedX, y: translatedY)
    }
    
    func clearCanvas() {
        saveUndoState()
        drawnPaths.removeAll()
        canvasImage = nil
        needsDisplay = true
    }

    private func initializeCanvasIfNeeded() {
        if canvasImage == nil {
            canvasImage = NSImage(size: canvasRect.size)
            canvasImage?.lockFocus()
            NSColor.white.set()
            NSBezierPath(rect: bounds).fill()
            canvasImage?.unlockFocus()
        }
    }
    
    func deleteSelectionOrPastedImage() {
        saveUndoState()
        if isPastingActive {
            // Clear the uncommitted pasted content
            pastedImage = nil
            pastedImageOrigin = nil
            pasteDragOffset = nil
            pasteImageStartOrigin = nil
            pasteDragStartPoint = nil
            isDraggingPastedImage = false
            isPastingImage = false
            isPastingActive = false
            needsDisplay = true
            return
        }

        if let rect = selectionRect {
            initializeCanvasIfNeeded()
            canvasImage?.lockFocus()
            NSColor.white.set()
            NSBezierPath(rect: rect).fill()
            canvasImage?.unlockFocus()

            drawnPaths.removeAll { (path, _) in
                    return path.bounds.intersects(rect)
                }
            
            selectionRect = nil
            selectedImage = nil
            needsDisplay = true
        }
    }

    func pickColor(at point: NSPoint) -> NSColor? {
        let flippedPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        let x = Int(flippedPoint.x)
        let y = Int(flippedPoint.y)

        guard x >= 0, y >= 0, x < Int(bounds.width), y < Int(bounds.height) else {
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
            return nil
        }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // ⬇️ Redraw everything
        NSColor.white.setFill()
        bounds.fill()

        canvasImage?.draw(in: canvasRect)

        for (path, color) in drawnPaths {
            color.setStroke()
            path.stroke()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // 🟡 Sample color at pixel
        guard let color = rep.colorAt(x: x, y: y) else {
            return nil
        }

        return color
    }

    func floodFill(from point: NSPoint, with fillColor: NSColor) {
        saveUndoState()
        let width = Int(canvasRect.width)
        let height = Int(canvasRect.height)
        
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
        canvasRect.fill()
        canvasImage?.draw(in: canvasRect)
        for (path, color) in drawnPaths {
            color.setStroke()
            path.stroke()
        }

        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return }

        let x = Int(point.x)
        let y = Int(canvasRect.height - point.y)
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
                break
            }
        }

        if canvasImage == nil {
            canvasImage = NSImage(size: canvasRect.size)
            canvasImage?.lockFocus()
            NSColor.white.setFill()
            canvasRect.fill()
            canvasImage?.unlockFocus()
        }

        canvasImage?.lockFocus()
        rep.draw(in: canvasRect)
        canvasImage?.unlockFocus()

        needsDisplay = true
    }
    
    func startSpray() {
        stopSpray() // Stop existing timer
        sprayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.spray()
        }
    }

    func spray() {
        initializeCanvasIfNeeded()
        canvasImage?.lockFocus()
        currentColor.setFill()

        for _ in 0..<sprayDensity {
            let angle = CGFloat.random(in: 0..<2*CGFloat.pi)
            let radius = CGFloat.random(in: 0..<sprayRadius)
            let x = currentSprayPoint.x + radius * cos(angle)
            let y = currentSprayPoint.y + radius * sin(angle)
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1, height: 1)).fill()
        }

        canvasImage?.unlockFocus()
        needsDisplay = true
    }

    func stopSpray() {
        sprayTimer?.invalidate()
        sprayTimer = nil
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let commandKey = event.modifierFlags.contains(.command)
        let char = event.charactersIgnoringModifiers?.lowercased()

        if commandKey {
            switch char {
            case "x": // ⌘X
                cutSelection()
                return true
            case "c": // ⌘C
                copySelection()
                return true
            case "v": // ⌘V
                pasteImage()
                return true
            case "a": // ⌘A - Select All and activate Select tool
                selectAllCanvas()
                currentTool = .select
                NotificationCenter.default.post(name: .toolChanged, object: PaintTool.select)
                needsDisplay = true
                return true
            case "z": // ⌘Z - Undo
                undo()
                return true
            case "y": // ⌘Y - Redo
                redo()
                return true
            default:
                break
            }
        } else if event.keyCode == 51 { // Delete key
            handleDeleteKey()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func selectAllCanvas() {
        let rect = canvasRect
        selectionRect = rect

        let image = NSImage(size: rect.size)
        image.lockFocus()
        canvasImage?.draw(at: .zero, from: rect, operation: .copy, fraction: 1.0)
        image.unlockFocus()

        selectedImage = image
        selectedImageOrigin = rect.origin
    }
    
    func pointsAreEqual(_ p1: NSPoint, _ p2: NSPoint) -> Bool {
        return Int(p1.x) == Int(p2.x) && Int(p1.y) == Int(p2.y)
    }
    
    @objc public func moveSelectionBy(dx: CGFloat, dy: CGFloat) {
        
        if selectedImage != nil, let image = selectedImage {
            if !hasMovedSelection {
                // Clear original area on first move
                canvasImage?.lockFocus()
                NSColor.white.setFill()
                if let io = selectedImageOrigin {
                    let selectionArea = NSRect(origin: io, size: image.size)
                    NSBezierPath(rect: selectionArea).fill()
                    canvasImage?.unlockFocus()
                    hasMovedSelection = true
                    drawnPaths.removeAll { (path, _) in
                        return path.bounds.intersects(selectionArea)
                    }
                }
            }
            needsDisplay = true
        }
        
        if isPastingActive, let origin = pastedImageOrigin {
            pastedImageOrigin = NSPoint(x: origin.x + dx, y: origin.y + dy)
            needsDisplay = true
        } else if let rect = selectionRect {
            selectionRect = rect.offsetBy(dx: dx, dy: dy)
            if let io = selectedImageOrigin {
                selectedImageOrigin = NSPoint(x: io.x + dx, y: io.y + dy)
            }
            needsDisplay = true
        }
    }

}

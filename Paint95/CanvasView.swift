import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func didPickColour(_ colour: NSColor)
    func canvasStatusDidChange(cursor: NSPoint, selectionSize: NSSize?)
}

// MARK: - Export snapshot (flattens any floating selection)
extension CanvasView {
    /// Returns a flattened image of the visible canvas, including any floating selection.
    func snapshotImageForExport() -> NSImage? {
        guard let base = canvasImage else { return nil }
        let size = canvasRect.size
        let out = NSImage(size: size)

        out.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        // Draw the base canvas
        base.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: base.size),
                  operation: .copy,
                  fraction: 1.0,
                  respectFlipped: true,
                  hints: [.interpolation: NSImageInterpolation.none])

        // If there’s a floating selection, draw it in place
        if let sel = selectedImage, let origin = selectedImageOrigin {
            sel.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        out.unlockFocus()
        return out
    }
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

extension CanvasView {
    /// Replace the backing raster and (optionally) clear any vector/path caches,
    /// so later tools (fill, pick colour) don't resurrect pre-transform pixels.
    func commitRasterChange(_ newImage: NSImage, resetVectors: Bool = true) {
        // Undo is handled by callers via saveUndoState()
        self.canvasImage = newImage

        if resetVectors {
            self.drawnPaths.removeAll()
        }

        // If the raster size changed, keep the logical canvas/view in sync.
        if self.canvasRect.size != newImage.size {
            self.canvasRect.origin = .zero
            _ = self.updateCanvasSize(to: newImage.size)
        }

        // Any uncommitted paste/selection preview is invalid after a global transform
        self.isPastingImage = false
        self.isPastingActive = false
        self.pastedImage = nil
        self.pastedImageOrigin = nil

        self.needsDisplay = true
    }
    
    /// Resize the canvas to `newSize`, preserving existing pixels anchored at the TOP-LEFT corner.
    /// Adds white space (right/bottom) when growing; crops from the bottom/right when shrinking.
    /// Uses the app's undo stack (image+rect), so Undo restores pixels *and* size with no scaling.
    func setCanvasSizeAnchoredTopLeft(to newSize: NSSize) {
        initializeCanvasIfNeeded()
        saveUndoState()

        guard let image = canvasImage else {
            canvasRect.origin = .zero
            canvasRect.size   = newSize
            setFrameSize(newSize)
            invalidateIntrinsicContentSize()
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            return
        }

        let oldSize = image.size
        let drawW = min(oldSize.width,  newSize.width)
        let drawH = min(oldSize.height, newSize.height)

        // choose TOP-LEFT piece from the old image
        let srcY = max(0, oldSize.height - drawH)
        let srcRect = NSRect(x: 0, y: srcY, width: drawW, height: drawH)

        // ⬇️ always paste at (0,0) so bottom-left of kept content is at (0,0)
        let dstRect = NSRect(x: 0, y: 0, width: drawW, height: drawH)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()
        image.draw(in: dstRect,
                   from: srcRect,
                   operation: .copy,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.none])
        newImage.unlockFocus()

        // Bake + clear vectors; commitRasterChange will zero the origin
        commitRasterChange(newImage, resetVectors: true)

        // Keep the scroll view in sync right away
        setFrameSize(newSize)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    
    /// Restores a previous canvas image and rect exactly, and registers the inverse for redo.
    private func restoreCanvas(image: NSImage?, rect: NSRect) {
        let prevImage = canvasImage?.copy() as? NSImage
        let prevRect  = canvasRect

        canvasImage = image?.copy() as? NSImage
        canvasRect  = rect
        updateCanvasSize(to: rect.size)
        needsDisplay = true

        // Redo support: swap back to what we had before restore
        undoManager?.registerUndo(withTarget: self) { me in
            me.restoreCanvas(image: prevImage, rect: prevRect)
        }
        undoManager?.setActionName("Canvas Size")
    }
}

class CanvasView: NSView {
    
    weak var delegate: CanvasViewDelegate?
    private var colourWindowController: ColourSelectionWindowController?
    
    var currentColour: NSColor {
        get { primaryColour }
        set { primaryColour = newValue }
    } // = .black
    var primaryColour: NSColor = .black
    var secondaryColour: NSColor = .white
    enum ActiveColourSlot { case primary, secondary }
    var activeColourSlot: ActiveColourSlot = .primary

    var canvasImage: NSImage? = nil
    var currentPath: NSBezierPath?
    var startPoint: NSPoint = .zero
    var endPoint: NSPoint = .zero
    var isDrawingShape: Bool = false

    var drawnPaths: [(path: NSBezierPath, colour: NSColor)] = []
    var colourFromSelectionWindow: Bool = false
    
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
    
    // NEW: one-time clear tracking for current floating selection
    private var clearedOriginalAreaForCurrentSelection = false

    //canvas re-size
    enum ResizeHandle: Int {
        case bottomLeft = 0, bottomCenter, bottomRight
        case middleLeft, middleRight
        case topLeft, topCenter, topRight
    }
    let handleSize: CGFloat = 5
    private let handleHitSlop: CGFloat = 6   // extra clickable area around each canvas handle
    var activeResizeHandle: ResizeHandle? = nil
    var isResizingCanvas = false
    var dragStartPoint: NSPoint = .zero
    var initialCanvasRect: NSRect = .zero
    var canvasRect = NSRect(x: 0, y: 0, width: 600, height: 400)
    var handlePositions: [NSPoint] {
        let offset = handleSize / 2
        return [
            // bottom row
            NSPoint(x: canvasRect.minX - offset, y: canvasRect.minY - offset),              // bottom-left
            NSPoint(x: canvasRect.midX - offset, y: canvasRect.minY - offset),              // bottom-center
            NSPoint(x: canvasRect.maxX - offset, y: canvasRect.minY - offset),              // bottom-right
            // middle
            NSPoint(x: canvasRect.minX - offset, y: canvasRect.midY - offset),              // middle-left
            NSPoint(x: canvasRect.maxX - offset, y: canvasRect.midY - offset),              // middle-right
            // top row
            NSPoint(x: canvasRect.minX - offset, y: canvasRect.maxY - offset),              // top-left
            NSPoint(x: canvasRect.midX - offset, y: canvasRect.maxY - offset),              // top-center
            NSPoint(x: canvasRect.maxX - offset, y: canvasRect.maxY - offset)               // top-right
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
    private let edgeGrabThickness: CGFloat = 6     // how close to an edge to start resizing
    private let cornerGrabSize: CGFloat = 12       // square size around corners for diagonal resize
    
    //Zoom
    var isZoomed: Bool = false
    var zoomRect: NSRect = .zero
    var zoomScale: CGFloat = 1.0
    var mousePosition: NSPoint = .zero
    override var intrinsicContentSize: NSSize {
        return isZoomed
            ? NSSize(width: canvasRect.width * zoomScale,
                     height: canvasRect.height * zoomScale)
            : canvasRect.size
    }
    
    // MARK: Zoom preview
    private var zoomPreviewRect: NSRect? {
        didSet { needsDisplay = true }
    }

    var currentTool: PaintTool = .pencil {
        didSet {
            // Clear zoom preview whenever we leave Zoom
            if currentTool != .zoom {
                zoomPreviewRect = nil
            }

            // 🔁 Auto-commit any floating selection/paste when switching to a non-Select tool
            if currentTool != .select,
               let _ = selectedImage, let _ = selectedImageOrigin {
                if isPastingActive {
                    commitPastedImage()   // also clears paste flags
                } else {
                    commitSelection()     // draws selection into the canvas and clears selection state
                }
            }
        }
    }
    
    //spray paint
    var sprayTimer: Timer?
    let sprayRadius: CGFloat = 10
    let sprayDensity: Int = 30
    var currentSprayPoint: NSPoint = .zero
    
    // Undo/Redo
    private struct CanvasSnapshot {
        let image: NSImage?
        let rect:  NSRect
    }
    private var undoStack: [CanvasSnapshot] = []
    private var redoStack: [CanvasSnapshot] = []
    private let maxUndoSteps = 5
    private var cancelCurvePreview = false
    
    // Scroll
    override var isOpaque: Bool { true }  // avoids transparent compositing
    override var wantsUpdateLayer: Bool { false }
    private var savedElasticity: (v: NSScrollView.Elasticity, h: NSScrollView.Elasticity)?
    private weak var freezeClip: NSClipView?
    private var  freezeOrigin: NSPoint?
    private var  isFreezeActive: Bool { freezeClip != nil }
    
    @objc dynamic var drawOpaque: Bool = true   // default ON like classic Paint
    
    func setActiveColour(_ colour: NSColor, for slot: ActiveColourSlot) {
        switch slot {
        case .primary: primaryColour = colour
        case .secondary: secondaryColour = colour
        }
        needsDisplay = true
    }
    
    private func emitStatusUpdate(cursor: NSPoint) {
        let selSize: NSSize?
        if let img = selectedImage, let _ = selectedImageOrigin {
            selSize = img.size
        } else if let rect = selectionRect {
            selSize = rect.size
        } else {
            selSize = nil
        }
        delegate?.canvasStatusDidChange(cursor: cursor, selectionSize: selSize)
    }
    
    func colourSelectedFromPalette(_ colour: NSColor) {
        SharedColour.currentColour = colour
        SharedColour.source = .palette

        // Approximate RGB from NSColor
        if let rgbColour = colour.usingColorSpace(.deviceRGB) {
            SharedColour.rgb = [
                Double(rgbColour.redComponent * 255.0),
                Double(rgbColour.greenComponent * 255.0),
                Double(rgbColour.blueComponent * 255.0)
            ]
        }

        self.currentColour = colour
        needsDisplay = true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(colourPicked(_:)), name: .colourPicked, object: nil)
        let trackingArea = NSTrackingArea(rect: self.bounds,
                                          options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        self.addTrackingArea(trackingArea)
    }

    @objc func colourPicked(_ notification: Notification) {
        if let newColour = notification.object as? NSColor {
            setActiveColour(newColour, for: activeColourSlot)
            colourFromSelectionWindow = true
            needsDisplay = true
        }
    }
    
    func showColourSelectionWindow() {
        // 1) Start from the ACTIVE swatch (primary or secondary)
        let baseColour: NSColor = (activeColourSlot == .primary) ? primaryColour : secondaryColour
        let rgb = baseColour.usingColorSpace(.deviceRGB) ?? baseColour
        let initial: [Double] = [
            Double(rgb.redComponent * 255.0),
            Double(rgb.greenComponent * 255.0),
            Double(rgb.blueComponent * 255.0)
        ]

        // 2) Build controller
        let controller = ColourSelectionWindowController(
            initialRGB: initial,
            onColourSelected: { [weak self] newColour in
                guard let self = self else { return }

                // Update the correct swatch that is active
                self.setActiveColour(newColour, for: self.activeColourSlot)

                // Broadcast for preview/live UI that are already listening
                NotificationCenter.default.post(name: .colourPicked, object: newColour)

                // Also broadcast a "commit" with explicit RGB so any owner of initialR/G/B syncs
                if let dev = newColour.usingColorSpace(.deviceRGB) {
                    let r = Int(round(dev.redComponent   * 255.0))
                    let g = Int(round(dev.greenComponent * 255.0))
                    let b = Int(round(dev.blueComponent  * 255.0))
                    NotificationCenter.default.post(
                        name: .colourCommitted,
                        object: nil,
                        userInfo: ["r": r, "g": g, "b": b]
                    )
                }

                // Release window controller
                self.colourWindowController = nil
            },
            onCancel: { [weak self] in
                self?.colourWindowController = nil
            }
        )

        // 3) Present
        colourWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setCurrentColour(_ colour: NSColor) {
        currentColour = colour
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

            // Draw the WHOLE canvas scaled. Scrolling now pans naturally.
            let dest = NSRect(x: 0, y: 0,
                              width:  canvasRect.width  * zoomScale,
                              height: canvasRect.height * zoomScale)
            image.draw(in: dest,
                       from: NSRect(origin: .zero, size: canvasRect.size),
                       operation: .copy,
                       fraction: 1.0,
                       respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.none])

        } else {
            canvasImage?.draw(in: canvasRect)

            // Zoom preview box when not zoomed yet
            if currentTool == .zoom, let zr = zoomPreviewRect {
                NSColor.black.setStroke()
                let path = NSBezierPath(rect: zr)
                path.lineWidth = 1
                path.stroke()
            }
        }

        // === Selected image / marquee preview ===
        if let image = selectedImage, let io = selectedImageOrigin {
            if isZoomed {
                let dest = NSRect(origin: toZoomed(io),
                                  size: NSSize(width: image.size.width  * zoomScale,
                                               height: image.size.height * zoomScale))

                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: 0,
                                          width:  canvasRect.width  * zoomScale,
                                          height: canvasRect.height * zoomScale)).addClip()
                image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()

                NSColor.black.setStroke()
                let path = NSBezierPath(rect: dest)
                path.setLineDash([5.0, 3.0], count: 2, phase: 0)
                path.lineWidth = 1
                path.stroke()

                // selection handles (scaled)
                let handleSize: CGFloat = 6 * zoomScale
                NSColor.systemBlue.setFill()
                for p in [
                    NSPoint(x: dest.minX - handleSize/2, y: dest.minY - handleSize/2),
                    NSPoint(x: dest.midX - handleSize/2, y: dest.minY - handleSize/2),
                    NSPoint(x: dest.maxX - handleSize/2, y: dest.minY - handleSize/2),
                    NSPoint(x: dest.minX - handleSize/2, y: dest.midY - handleSize/2),
                    NSPoint(x: dest.maxX - handleSize/2, y: dest.midY - handleSize/2),
                    NSPoint(x: dest.minX - handleSize/2, y: dest.maxY - handleSize/2),
                    NSPoint(x: dest.midX - handleSize/2, y: dest.maxY - handleSize/2),
                    NSPoint(x: dest.maxX - handleSize/2, y: dest.maxY - handleSize/2),
                ] {
                    NSBezierPath(rect: NSRect(x: p.x, y: p.y, width: handleSize, height: handleSize)).fill()
                }

            } else {
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
                NSColor.systemBlue.setFill()
                for p in [
                    NSPoint(x: selectionFrame.minX - handleSize/2, y: selectionFrame.minY - handleSize/2),
                    NSPoint(x: selectionFrame.midX - handleSize/2, y: selectionFrame.minY - handleSize/2),
                    NSPoint(x: selectionFrame.maxX - handleSize/2, y: selectionFrame.minY - handleSize/2),
                    NSPoint(x: selectionFrame.minX - handleSize/2, y: selectionFrame.midY - handleSize/2),
                    NSPoint(x: selectionFrame.maxX - handleSize/2, y: selectionFrame.midY - handleSize/2),
                    NSPoint(x: selectionFrame.minX - handleSize/2, y: selectionFrame.maxY - handleSize/2),
                    NSPoint(x: selectionFrame.midX - handleSize/2, y: selectionFrame.maxY - handleSize/2),
                    NSPoint(x: selectionFrame.maxX - handleSize/2, y: selectionFrame.maxY - handleSize/2),
                ] {
                    NSBezierPath(rect: NSRect(x: p.x, y: p.y, width: handleSize, height: handleSize)).fill()
                }
            }

        } else if let rect = selectionRect {
            if isZoomed {
                let rZ = toZoomed(rect)
                NSColor.black.setStroke()
                let path = NSBezierPath(rect: rZ)
                path.setLineDash([5.0, 3.0], count: 2, phase: 0)
                path.lineWidth = 1
                path.stroke()
            } else {
                NSColor.black.setStroke()
                let path = NSBezierPath(rect: rect)
                path.setLineDash([5.0, 3.0], count: 2, phase: 0)
                path.lineWidth = 1
                path.stroke()
            }
        }

        // === Curve / shapes / text previews ===
        if currentTool == .curve && !cancelCurvePreview {
            var start = startPoint, end = endPoint, c1 = control1, c2 = control2
            if isZoomed { start = toZoomed(start); end = toZoomed(end); c1 = toZoomed(c1); c2 = toZoomed(c2) }

            let path = NSBezierPath()
            path.lineWidth = toolSize * (isZoomed ? zoomScale : 1)
            currentColour.set()
            switch curvePhase {
            case 0: if start != end { path.move(to: start); path.line(to: end); path.stroke() }
            case 1: path.move(to: start); path.curve(to: end, controlPoint1: c1, controlPoint2: c1); path.stroke()
            case 2: path.move(to: start); path.curve(to: end, controlPoint1: c1, controlPoint2: c2); path.stroke()
            default: break
            }
            cancelCurvePreview = false

        } else if isDrawingShape {
            currentColour.set()
            var start = startPoint, end = endPoint
            if isZoomed { start = toZoomed(start); end = toZoomed(end) }
            if let shapePath = shapePathBetween(start, end) {
                shapePath.lineWidth = toolSize * (isZoomed ? zoomScale : 1)
                shapePath.stroke()
            }

        } else if isCreatingText {
            NSColor.gray.setStroke()
            let r = isZoomed ? toZoomed(textBoxRect) : textBoxRect
            let path = NSBezierPath(rect: r)
            path.setLineDash([4, 2], count: 2, phase: 0)
            path.lineWidth = 1
            path.stroke()
        }

        // === Canvas border (no handles) ===
        if isZoomed {
            let border = NSRect(x: 0, y: 0, width: canvasRect.width * zoomScale, height: canvasRect.height * zoomScale)
            NSColor.black.setStroke()
            NSBezierPath(rect: border).stroke()
        } else {
            NSColor.black.setStroke()
            NSBezierPath(rect: canvasRect).stroke()

            if currentTool == .zoom, let r = zoomPreviewRect {
                NSColor.keyboardFocusIndicatorColor.setStroke()
                let path = NSBezierPath(rect: r)
                path.setLineDash([4, 4], count: 2, phase: 0)
                path.stroke()
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        zoomPreviewRect = nil
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
        emitStatusUpdate(cursor: point)

        // === Selection handle detection (resize) ===
        if let rect = selectionRect ?? (selectedImage != nil ? NSRect(origin: selectedImageOrigin ?? .zero, size: selectedImage!.size) : nil) {
            for (i, handle) in selectionHandlePositions(rect: rect).enumerated() {
                if handle.contains(point) {
                    saveUndoState()  // <-- checkpoint before selection resize
                    activeSelectionHandle = SelectionHandle(rawValue: i)
                    isResizingSelection = true
                    resizeStartPoint = point
                    originalSelectionRect = rect
                    originalSelectedImage = selectedImage
                    return
                }
            }
        }

        // === Canvas border/corner detection ===
        if let h = resizeHandle(at: point) {
            saveUndoState()
            activeResizeHandle = h
            isResizingCanvas = true
            dragStartPoint = point
            initialCanvasRect = canvasRect
            beginScrollFreezeIfNeeded()
            return
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
                        // Mark as cleared-once for this floating selection
                        clearedOriginalAreaForCurrentSelection = true
                        hasMovedSelection = true
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
            if let picked = pickColour(at: point) {
                currentColour = picked
                NotificationCenter.default.post(name: .colourPicked, object: picked)
                colourFromSelectionWindow = false
            }

        case .pencil, .brush, .eraser:
            saveUndoState()  // <-- checkpoint at stroke start
            startPoint = point
            currentPath = NSBezierPath()
            currentPath?.move(to: point)

        case .fill:
            saveUndoState()
            floodFill(from: point, with: currentColour)

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
                // Exit zoom
                isZoomed = false
                zoomScale = 1.0
                updateZoomDocumentSize()
                needsDisplay = true
            } else {
                // Enter zoom using the current preview box if available
                let p = convert(event.locationInWindow, from: nil)
                let zr = zoomPreviewRect ?? NSRect(x: p.x - 64, y: p.y - 64, width: 128, height: 128)

                // Use the scrollview’s visible size as our viewport
                let viewport = (enclosingScrollView?.contentView.bounds.size) ?? bounds.size

                // Uniform scale so zr * scale fits in viewport
                let sx = max(1, viewport.width  / max(1, zr.width))
                let sy = max(1, viewport.height / max(1, zr.height))
                zoomScale = min(sx, sy)

                isZoomed = true
                updateZoomDocumentSize()

                // Scroll so the zoomed preview rect is visible
                let target = NSRect(x: zr.origin.x * zoomScale,
                                    y: zr.origin.y * zoomScale,
                                    width:  zr.size.width  * zoomScale,
                                    height: zr.size.height * zoomScale)
                scrollToVisible(target)

                needsDisplay = true
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
        let shiftPressed = event.modifierFlags.contains(.shift)
        emitStatusUpdate(cursor: point)
        
        // === Selection resizing (reuse for pasted content; non-destructive while pasting) ===
        if isResizingSelection, let handle = activeSelectionHandle {
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
                newRect.size.width  -= dx
                newRect.size.height -= dy
            case .bottomCenter:
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .bottomRight:
                newRect.origin.y += dy
                newRect.size.height -= dy
                newRect.size.width  += dx
            case .middleLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
            case .middleRight:
                newRect.size.width += dx
            case .topLeft:
                newRect.origin.x += dx
                newRect.size.width  -= dx
                newRect.size.height += dy
            case .topCenter:
                newRect.size.height += dy
            case .topRight:
                newRect.size.width  += dx
                newRect.size.height += dy
            }

            // Enforce min size while keeping the *opposite* edge anchored:
            if newRect.width < 50 {
                switch handle {
                case .bottomLeft, .middleLeft, .topLeft:
                    newRect.origin.x = initialCanvasRect.maxX - 50
                default: break
                }
                newRect.size.width = 50
            }
            if newRect.height < 50 {
                switch handle {
                case .bottomLeft, .bottomCenter, .bottomRight:
                    newRect.origin.y = initialCanvasRect.maxY - 50
                default: break
                }
                newRect.size.height = 50
            }

            // 🔴 Preview only: update the model rect and redraw. Do NOT touch the view frame here.
            canvasRect = newRect
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
            let shiftPressed = event.modifierFlags.contains(.shift)
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
        if currentTool != .zoom { zoomPreviewRect = nil }
        if isResizingCanvas {
            isResizingCanvas = false

            // Remember which axes went negative during the drag,
            // BEFORE the commit resets canvasRect.origin to (0,0)
            let needZeroX = canvasRect.minX < 0
            let needZeroY = canvasRect.minY < 0

            let handleUsed = activeResizeHandle
            cropCanvasImageToCanvasRect(using: handleUsed)   // commits pixels, re-calibrates to (0,0)
            activeResizeHandle = nil

            //endScrollFreeze()
            
            // Defer to next runloop so NSScrollView finishes its own adjustments first
            if let sv = enclosingScrollView {
                DispatchQueue.main.async { [weak self, weak sv] in
                    guard let self = self, let sv = sv else { return }
                    let clip = sv.contentView

                    if let h = handleUsed {
                        let w = self.canvasRect.width
                        let hgt = self.canvasRect.height
                        let anchorRect: NSRect
                        switch h {
                        case .topRight:     anchorRect = NSRect(x: w - 1, y: hgt - 1, width: 1, height: 1)
                        case .topCenter:    anchorRect = NSRect(x: w / 2,  y: hgt - 1, width: 1, height: 1)
                        case .middleRight:  anchorRect = NSRect(x: w - 1,  y: hgt / 2, width: 1, height: 1)
                        case .topLeft:      anchorRect = NSRect(x: 1,      y: hgt - 1, width: 1, height: 1)
                        case .bottomRight:  anchorRect = NSRect(x: w - 1,  y: 1,       width: 1, height: 1)
                        case .bottomCenter: anchorRect = NSRect(x: w / 2,  y: 1,       width: 1, height: 1)
                        case .middleLeft:   anchorRect = NSRect(x: 1,      y: hgt / 2, width: 1, height: 1)
                        case .bottomLeft:   anchorRect = NSRect(x: 0,      y: 0,       width: 1, height: 1)
                        }
                        self.scrollToVisible(anchorRect)
                    }
                }
            }

            needsDisplay = true
            return
        }

        if isResizingSelection {
            isResizingSelection = false
            activeSelectionHandle = nil
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
        emitStatusUpdate(cursor: point)

        if let image = selectedImage, let io = selectedImageOrigin {
            let rect = NSRect(origin: io, size: image.size)
            if !rect.contains(point) {
                commitSelection()
                return
            }
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
            // Reset one-time clear flag for this new floating selection
            clearedOriginalAreaForCurrentSelection = false
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
                currentColour.set()
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
                currentColour.set()
                let brushSize = max(1, toolSize) // match selector size
                let dotRect = NSRect(x: startPoint.x - brushSize/2,
                                     y: startPoint.y - brushSize/2,
                                     width: brushSize,
                                     height: brushSize)
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
                currentColour.set()
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
                currentColour.set()
                translatedPath.stroke()
                canvasImage?.unlockFocus()
                drawnPaths.append((path: translatedPath.copy() as! NSBezierPath, colour: currentColour))
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
        
        guard currentTool == .zoom else { return }
            let p = convert(event.locationInWindow, from: nil)
            let box: CGFloat = 64
            zoomPreviewRect = NSRect(x: p.x - box/2, y: p.y - box/2, width: box, height: box)

        let point = convert(event.locationInWindow, from: nil)
        emitStatusUpdate(cursor: convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil)))
        
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
    
    override func mouseExited(with event: NSEvent) {
        zoomPreviewRect = nil
    }
    
    override func keyDown(with event: NSEvent) {
        guard event.type == .keyDown else { return }

        // Handle Command-shortcuts first
        if event.modifierFlags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                // add command-key cases here if desired
                default:
                    break
                }
            }
        }
        // Commit paste on Return while actively pasting
        else if isPastingActive, let characters = event.charactersIgnoringModifiers {
            if characters == "\r" || characters == "\n" {
                commitPastedImage()
                return
            }
        }

        let key = event.keyCode

        // ---- Arrow-key movement (selection or pasted overlay) ----
        let isArrow = (key == 123 || key == 124 || key == 125 || key == 126)
        if isArrow {
            // NEW: if we’re actively pasting, nudge the overlay without clearing underneath.
            if isPastingActive, let img = selectedImage, let origin = selectedImageOrigin {
                var newOrigin = origin
                switch key {
                case 123: newOrigin.x -= 1    // ←
                case 124: newOrigin.x += 1    // →
                case 125: newOrigin.y -= 1    // ↓
                case 126: newOrigin.y += 1    // ↑
                default: break
                }
                // Keep both the selection and paste overlay in sync
                selectedImageOrigin = newOrigin
                selectionRect = NSRect(origin: newOrigin, size: img.size)
                pastedImageOrigin = newOrigin
                needsDisplay = true
                emitStatusUpdate(cursor: mousePosition)
                return
            }
            
            var dx: CGFloat = 0, dy: CGFloat = 0
            switch key {
            case 123: dx = -1      // ←
            case 124: dx =  1      // →
            case 125: dy = -1      // ↓
            case 126: dy =  1      // ↑
            default: break
            }
            moveSelectionBy(dx: dx, dy: dy) // handles both floating selection and pasted overlay
            return
        }

        // Return (Enter) commits the floating/pasted image
        if key == 36 { // Return
            commitSelection()
            return
        }

        // Delete cancels paste or clears selection area
        if key == 51 || key == 117 { // Delete / Forward Delete
            deleteSelectionOrPastedImage()
            return
        }

        super.keyDown(with: event)
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
    
    // Promote the current rectangular selection to a floating bitmap and
    // CUT the pixels from the canvas once (no-op if already floating).
    private func cutSelectionToFloatingIfNeeded() {
        guard selectedImage == nil,                         // not floating yet
              let rect = selectionRect,                    // have a selection
              let base = canvasImage,                      // have pixels to cut
              rect.width > 0, rect.height > 0
        else { return }

        // 1) Copy the selected pixels into a new image (the “floating” selection)
        let img = NSImage(size: rect.size)
        img.lockFocus()
        base.draw(at: .zero, from: rect, operation: .copy, fraction: 1.0)
        img.unlockFocus()
        selectedImage = img

        // 2) CUT (clear) the original region on the canvas
        base.lockFocus()
        NSColor.white.setFill() // or a background color if you support one
        rect.fill()
        base.unlockFocus()

        // Mark one-time clear complete
        clearedOriginalAreaForCurrentSelection = true
        hasMovedSelection = true

        // Keep selectionRect as the floating rect (same origin to start)
        // (If you track a separate floating origin, update that instead.)
    }

    /// Clear the original pixels under the *current* floating selection exactly once.
    /// No-ops if (a) already cleared, (b) no floating selection, or (c) we're pasting.
    private func ensureOriginalAreaClearedIfNeeded() {
        guard !clearedOriginalAreaForCurrentSelection,
              !isPastingActive,
              let img = selectedImage,
              let origin = selectedImageOrigin
        else { return }

        saveUndoState()
        let clearRect = NSRect(origin: origin, size: img.size)

        // Clear pixels on the canvas
        clearCanvasRegion(rect: clearRect, lockFocus: true)

        // Remove vector strokes that overlapped that region (clearCanvasRegion already does this).
        drawnPaths.removeAll { $0.path.bounds.intersects(clearRect) }

        clearedOriginalAreaForCurrentSelection = true
        hasMovedSelection = true
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
        
        // If a floating selection is active, commit it to the canvas
        // before pasting a copy from the pasteboard.
        if selectedImage != nil, selectedImageOrigin != nil {
            commitSelection()
        }

        guard
            let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
            var img = images.first
        else { return }

        // ── NEW: apply color-key transparency if Draw Opaque is OFF ───────────────
        if !drawOpaque {
            // Use your app's background/secondary colour here if you track one:
            let keyColour = NSColor.white
            if let keyed = imageByMakingColorTransparent(img, key: keyColour, tolerance: 0.02) {
                img = keyed
            }
        }
        // ─────────────────────────────────────────────────────────────────────────

        // Clear any old selection state
        selectionRect = nil
        selectedImage = nil
        selectedImageOrigin = nil

        // Start Paste Mode (overlay)
        let origin = NSPoint(x: 100, y: 100)
        pastedImage = img
        pastedImageOrigin = origin
        isPastingImage = true
        isPastingActive = true
        hasMovedSelection = false

        // Make the pasted content the active "selection"
        selectedImage = img
        selectedImageOrigin = origin
        selectionRect = NSRect(origin: origin, size: img.size)

        // Overlay should never pre-clear underneath; reset one-time flag
        clearedOriginalAreaForCurrentSelection = false

        // Scroll to show pasted content
        if let clipView = superview as? NSClipView {
            clipView.scrollToVisible(NSRect(origin: origin, size: img.size))
        }

        // Ensure the canvas is large enough to show it; grow if needed.
        let requiredWidth  = max(canvasRect.width,  origin.x + img.size.width)
        let requiredHeight = max(canvasRect.height, origin.y + img.size.height)
        if requiredWidth != canvasRect.width || requiredHeight != canvasRect.height {
            updateCanvasSize(to: NSSize(width: requiredWidth, height: requiredHeight))
        }

        // Ensure the selection tool is active so move/resize works
        currentTool = .select
        NotificationCenter.default.post(name: .toolChanged, object: PaintTool.select)

        self.window?.makeFirstResponder(self)
        needsDisplay = true
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
            clearedOriginalAreaForCurrentSelection = false
            hasMovedSelection = false
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
        clearedOriginalAreaForCurrentSelection = false
        hasMovedSelection = false
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
        clearedOriginalAreaForCurrentSelection = false
        hasMovedSelection = false
        needsDisplay = true
    }
    
    func selectionHandlePositions(rect: NSRect) -> [NSRect] {
        let size: CGFloat = 6
        let half = size / 2

        // Order must match SelectionHandle raw values
        let tl = NSRect(x: rect.minX - half, y: rect.maxY - half, width: size, height: size) // top-left
        let tc = NSRect(x: rect.midX - half, y: rect.maxY - half, width: size, height: size) // top-center
        let tr = NSRect(x: rect.maxX - half, y: rect.maxY - half, width: size, height: size) // top-right
        let ml = NSRect(x: rect.minX - half, y: rect.midY - half, width: size, height: size) // middle-left
        let mr = NSRect(x: rect.maxX - half, y: rect.midY - half, width: size, height: size) // middle-right
        let bl = NSRect(x: rect.minX - half, y: rect.minY - half, width: size, height: size) // bottom-left
        let bc = NSRect(x: rect.midX - half, y: rect.minY - half, width: size, height: size) // bottom-center
        let br = NSRect(x: rect.maxX - half, y: rect.minY - half, width: size, height: size) // bottom-right

        return [tl, tc, tr, ml, mr, bl, bc, br]
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
            .foregroundColor: currentColour
        ]
        
        let attributed = NSAttributedString(string: text, attributes: textAttributes)
        attributed.draw(in: tv.frame)

        canvasImage?.unlockFocus()
        tv.removeFromSuperview()
        textView = nil
        needsDisplay = true
    }
    
    // REPLACE saveUndoState() with this:
    private func saveUndoState() {
        // snapshot even if image is nil (e.g., clearing/new doc) so size is tracked too
        let snap = CanvasSnapshot(image: canvasImage?.copy() as? NSImage, rect: canvasRect)
        if undoStack.count >= maxUndoSteps { undoStack.removeFirst() }
        undoStack.append(snap)
        redoStack.removeAll()
    }

    // REPLACE undo() with this:
    @objc func undo() {
        guard let last = undoStack.popLast() else { return }
        let current = CanvasSnapshot(image: canvasImage?.copy() as? NSImage, rect: canvasRect)
        redoStack.append(current)
        applySnapshot(last)
    }

    // REPLACE redo() with this:
    @objc func redo() {
        guard let next = redoStack.popLast() else { return }
        let current = CanvasSnapshot(image: canvasImage?.copy() as? NSImage, rect: canvasRect)
        undoStack.append(current)
        applySnapshot(next)
    }

    // ADD this small helper:
    private func applySnapshot(_ snap: CanvasSnapshot) {
        canvasImage = snap.image?.copy() as? NSImage
        canvasRect  = snap.rect

        // Keep view/scroll sizing in sync WITHOUT re-rendering pixels.
        setFrameSize(snap.rect.size)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)

        // Reset curve preview state after timeline ops
        curvePhase = 0
        curveStart = .zero
        curveEnd = .zero
        control1 = .zero
        control2 = .zero
        cancelCurvePreview = false

        needsDisplay = true
    }
    
    private func cropCanvasImageToCanvasRect(using handle: ResizeHandle?) {
        guard let old = canvasImage else {
            // No pixels yet—just size the view/document and snap to (0,0)
            let newSize = canvasRect.size
            canvasRect = NSRect(origin: .zero, size: newSize)
            setFrameSize(newSize)
            invalidateIntrinsicContentSize()
            window?.invalidateCursorRects(for: self)
            return
        }

        // Map handle → the *opposite* anchor we keep existing pixels stuck to.
        enum AnchorX { case left, center, right }
        enum AnchorY { case bottom, center, top }
        func anchor(for handle: ResizeHandle?) -> (AnchorX, AnchorY) {
            switch handle {
            case .some(.bottomLeft):   return (.right, .top)     // grow BL ⇒ blank at BL
            case .some(.bottomCenter): return (.center, .top)    // grow bottom ⇒ blank at bottom
            case .some(.bottomRight):  return (.left,  .top)     // grow BR ⇒ blank at BR
            case .some(.middleLeft):   return (.right, .center)  // grow left ⇒ blank at left
            case .some(.middleRight):  return (.left,  .center)  // grow right ⇒ blank at right
            case .some(.topLeft):      return (.right, .bottom)  // grow TL ⇒ blank at TL
            case .some(.topCenter):    return (.center, .bottom) // grow top ⇒ blank at top
            case .some(.topRight):     return (.left,  .bottom)  // grow TR ⇒ blank at TR
            case .none:                return (.left,  .top)     // menu/default (classic TL anchor)
            }
        }

        let (ax, ay) = anchor(for: handle)

        let newSize = canvasRect.size
        let oldSize = old.size
        let drawW = min(oldSize.width,  newSize.width)
        let drawH = min(oldSize.height, newSize.height)

        // Source offsets inside the old image (which region survives)
        let srcX: CGFloat = {
            switch ax {
            case .left:   return 0
            case .center: return max(0, (oldSize.width  - drawW) / 2)
            case .right:  return max(0,  oldSize.width  - drawW)
            }
        }()
        let srcY: CGFloat = {
            // respectFlipped: true → top-origin math
            switch ay {
            case .top:    return max(0,  oldSize.height - drawH)
            case .center: return max(0, (oldSize.height - drawH) / 2)
            case .bottom: return 0
            }
        }()

        // Destination offsets inside the new image (where that region lands)
        let dstX: CGFloat = {
            switch ax {
            case .left:   return 0
            case .center: return max(0, (newSize.width  - drawW) / 2)
            case .right:  return max(0,  newSize.width  - drawW)
            }
        }()
        let dstY: CGFloat = {
            switch ay {
            case .top:    return max(0,  newSize.height - drawH)
            case .center: return max(0, (newSize.height - drawH) / 2)
            case .bottom: return 0
            }
        }()

        // Build new image (white background), copy overlap 1:1 (no scaling).
        let srcRect = NSRect(x: floor(srcX), y: floor(srcY), width: floor(drawW), height: floor(drawH))
        let dstRect = NSRect(x: floor(dstX), y: floor(dstY), width: floor(drawW), height: floor(drawH))

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()
        old.draw(in: dstRect,
                 from: srcRect,
                 operation: .copy,
                 fraction: 1.0,
                 respectFlipped: true,
                 hints: [.interpolation: NSImageInterpolation.none])
        newImage.unlockFocus()

        // Commit (drop vector cache to prevent ghost strokes)
        commitRasterChange(newImage, resetVectors: true)

        // Re-calibrate model/view to (0,0) and sync with the scroll view; leave actual
        // scroll position correction to mouseUp (deferred) to avoid AppKit overriding it.
        canvasRect = NSRect(origin: .zero, size: newSize)
        setFrameSize(newSize)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
    }
    
    // MARK: - Uniform zoom helpers (1:1 pixel aspect with letterboxing)
    private func updateZoomDocumentSize() {
        let size = isZoomed
            ? NSSize(width: floor(canvasRect.width  * zoomScale),
                     height: floor(canvasRect.height * zoomScale))
            : canvasRect.size

        setFrameSize(size)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
    }
    
    private func zoomScaleAndOffset() -> (scale: CGFloat, offset: NSPoint) {
        let s = min(canvasRect.width / zoomRect.width,
                    canvasRect.height / zoomRect.height)
        let ox = (canvasRect.width  - zoomRect.width  * s) * 0.5
        let oy = (canvasRect.height - zoomRect.height * s) * 0.5
        return (s, NSPoint(x: ox, y: oy))
    }

    private func toZoomed(_ p: NSPoint) -> NSPoint {
        return isZoomed ? NSPoint(x: p.x * zoomScale, y: p.y * zoomScale) : p
    }
    private func toZoomed(_ r: NSRect) -> NSRect {
        return isZoomed
            ? NSRect(x: r.origin.x * zoomScale,
                     y: r.origin.y * zoomScale,
                     width:  r.size.width * zoomScale,
                     height: r.size.height * zoomScale)
            : r
    }

    private func fromZoomed(_ p: NSPoint) -> NSPoint {
        let (s, o) = zoomScaleAndOffset()
        return NSPoint(x: zoomRect.origin.x + (p.x - o.x) / s,
                       y: zoomRect.origin.y + (p.y - o.y) / s)
    }

    
    func createTextView(in rect: NSRect) {
        textView?.removeFromSuperview()
        
        let tv = CanvasTextView(frame: rect)
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.backgroundColor = NSColor.white
        tv.textColor = currentColour
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
        currentColour.setStroke()
        transformedPath.stroke()
        image.unlockFocus()

        drawnPaths.append((path: transformedPath.copy() as! NSBezierPath, colour: currentColour))
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
        
        var strokeColour: NSColor
        var lineWidth: CGFloat

        switch currentTool {
        case .pencil:
            strokeColour = currentColour
            lineWidth = 1
        case .brush:
            strokeColour = currentColour
            lineWidth = toolSize
        case .eraser:
            strokeColour = .white
            lineWidth = toolSize * 3
        default:
            return
        }

        translatedPath.lineWidth = lineWidth

        // Draw to the canvas image
        canvasImage?.lockFocus()
        strokeColour.set()
        translatedPath.stroke()
        canvasImage?.unlockFocus()

        drawnPaths.append((path: translatedPath.copy() as! NSBezierPath, colour: strokeColour))

        currentPath = nil
        needsDisplay = true
    }
    
    private func resizeHandle(at p: NSPoint) -> ResizeHandle? {
        let r = canvasRect
        let edge = edgeGrabThickness
        let corner = cornerGrabSize

        // Corner first (diagonal only when near the corner square)
        let nearTopLeft     = abs(p.x - r.minX) <= corner && abs(p.y - r.maxY) <= corner
        let nearTopRight    = abs(p.x - r.maxX) <= corner && abs(p.y - r.maxY) <= corner
        let nearBottomLeft  = abs(p.x - r.minX) <= corner && abs(p.y - r.minY) <= corner
        let nearBottomRight = abs(p.x - r.maxX) <= corner && abs(p.y - r.minY) <= corner
        if nearTopLeft     { return .topLeft }
        if nearTopRight    { return .topRight }
        if nearBottomLeft  { return .bottomLeft }
        if nearBottomRight { return .bottomRight }

        // Otherwise any point along an edge is valid for 1-axis resize
        let onLeft   = abs(p.x - r.minX) <= edge && p.y >= r.minY - edge && p.y <= r.maxY + edge
        let onRight  = abs(p.x - r.maxX) <= edge && p.y >= r.minY - edge && p.y <= r.maxY + edge
        let onTop    = abs(p.y - r.maxY) <= edge && p.x >= r.minX - edge && p.x <= r.maxX + edge
        let onBottom = abs(p.y - r.minY) <= edge && p.x >= r.minX - edge && p.x <= r.maxX + edge

        if onTop    { return .topCenter }
        if onBottom { return .bottomCenter }
        if onLeft   { return .middleLeft }
        if onRight  { return .middleRight }

        return nil
    }
    
    private func resizeBackingImage(to newSize: NSSize) {
        if canvasImage == nil {
            // Create a fresh white image of the requested size
            let img = NSImage(size: newSize)
            img.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()
            img.unlockFocus()
            canvasImage = img
            return
        }

        guard let old = canvasImage else { return }
        let oldSize = old.size

        // Create the new canvas image (white background)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()

        // Copy the overlapping area 1:1 (no scaling)
        let copySize = NSSize(width: min(oldSize.width, newSize.width),
                              height: min(oldSize.height, newSize.height))
        let srcRect = NSRect(origin: .zero, size: copySize)
        let dstRect = srcRect // same size/origin => no scaling

        old.draw(in: dstRect,
                 from: srcRect,
                 operation: .copy,
                 fraction: 1.0,
                 respectFlipped: true,
                 hints: [.interpolation: NSImageInterpolation.none])

        newImage.unlockFocus()
        canvasImage = newImage
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()

        // Canvas → view coords (scale when zoomed)
        let s: CGFloat = isZoomed ? zoomScale : 1.0
        func scale(_ r: NSRect) -> NSRect {
            return isZoomed
                ? NSRect(x: r.origin.x * s, y: r.origin.y * s, width: r.size.width * s, height: r.size.height * s)
                : r
        }

        let rV = scale(canvasRect)
        let edge = edgeGrabThickness * s
        let corner = cornerGrabSize * s

        // Corner squares (give them priority)
        let tl = NSRect(x: rV.minX - corner, y: rV.maxY - corner, width: 2*corner, height: 2*corner)
        let tr = NSRect(x: rV.maxX - corner, y: rV.maxY - corner, width: 2*corner, height: 2*corner)
        let bl = NSRect(x: rV.minX - corner, y: rV.minY - corner, width: 2*corner, height: 2*corner)
        let br = NSRect(x: rV.maxX - corner, y: rV.minY - corner, width: 2*corner, height: 2*corner)

        // Edge bands (trimmed to avoid overlap with corners)
        let top    = NSRect(x: rV.minX + corner, y: rV.maxY - edge, width: rV.width - 2*corner, height: 2*edge)
        let bottom = NSRect(x: rV.minX + corner, y: rV.minY - edge, width: rV.width - 2*corner, height: 2*edge)
        let left   = NSRect(x: rV.minX - edge,   y: rV.minY + corner, width: 2*edge, height: rV.height - 2*corner)
        let right  = NSRect(x: rV.maxX - edge,   y: rV.minY + corner, width: 2*edge, height: rV.height - 2*corner)

        // Cursors
        func diagNWSE() -> NSCursor {
            return NSCursor(
                image: NSImage(byReferencingFile: "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northWestSouthEastResizeCursor.png")!,
                hotSpot: NSPoint(x: 8, y: 8))
        }
        func diagNESW() -> NSCursor {
            return NSCursor(
                image: NSImage(byReferencingFile: "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northEastSouthWestResizeCursor.png")!,
                hotSpot: NSPoint(x: 8, y: 8))
        }

        // Add rects (clip to our bounds to avoid warnings)
        for (rect, cursor) in [
            (tl, diagNWSE()), (br, diagNWSE()),
            (tr, diagNESW()), (bl, diagNESW()),
            (top, .resizeUpDown), (bottom, .resizeUpDown),
            (left, .resizeLeftRight), (right, .resizeLeftRight),
        ] {
            let clipped = rect.intersection(bounds)
            if !clipped.isEmpty { addCursorRect(clipped, cursor: cursor) }
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
    
    private func selectionCursorForHandle(index: Int) -> NSCursor {
        // SelectionHandle order: topLeft(0), topCenter(1), topRight(2),
        //                        middleLeft(3), middleRight(4),
        //                        bottomLeft(5), bottomCenter(6), bottomRight(7)
        switch index {
        case 1, 6:
            return .resizeUpDown
        case 3, 4:
            return .resizeLeftRight
        case 0, 2:
            // topLeft / topRight => diagonals
            return NSCursor(image: NSImage(byReferencingFile: "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northWestSouthEastResizeCursor.png")!, hotSpot: NSPoint(x: 8, y: 8))
        case 5, 7:
            // bottomLeft / bottomRight => opposite diagonals
            return NSCursor(image: NSImage(byReferencingFile: "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northEastSouthWestResizeCursor.png")!, hotSpot: NSPoint(x: 8, y: 8))
        default:
            return .arrow
        }
    }
    
    // View (scaled) → canvas (unscaled)
    func convertZoomedPointToCanvas(_ point: NSPoint) -> NSPoint {
        guard isZoomed else { return point }
        return NSPoint(x: point.x / zoomScale, y: point.y / zoomScale)
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
    
    // Kept for symmetry/back-compat; same mapping
    func convertZoomedPoint(_ point: NSPoint) -> NSPoint {
        guard isZoomed else { return point }
        return NSPoint(x: point.x / zoomScale, y: point.y / zoomScale)
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
            NSBezierPath(rect: NSRect(origin: .zero, size: canvasRect.size)).fill()
            canvasImage?.unlockFocus()

            // Ensure our view/frame matches the canvas
            updateCanvasSize(to: canvasRect.size)
        }
    }
    
    func deleteSelectionOrPastedImage() {
        saveUndoState()
        if isPastingActive {
            // Cancel paste: do NOT alter the canvas; just drop the overlay.
            pastedImage = nil
            pastedImageOrigin = nil
            pasteDragOffset = nil
            pasteImageStartOrigin = nil
            pasteDragStartPoint = nil
            isDraggingPastedImage = false
            isPastingImage = false
            isPastingActive = false
            selectedImage = nil
            selectedImageOrigin = nil
            selectionRect = nil
            clearedOriginalAreaForCurrentSelection = false
            hasMovedSelection = false
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
                path.bounds.intersects(rect)
            }

            selectionRect = nil
            selectedImage = nil
            selectedImageOrigin = nil
            clearedOriginalAreaForCurrentSelection = false
            hasMovedSelection = false
            needsDisplay = true
        }
    }

    func pickColour(at point: NSPoint) -> NSColor? {
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

        for (path, colour) in drawnPaths {
            colour.setStroke()
            path.stroke()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // 🟡 Sample colour at pixel
        guard let colour = rep.colorAt(x: x, y: y) else {
            return nil
        }

        return colour
    }

    func floodFill(from point: NSPoint, with fillColour: NSColor) {
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
        for (path, colour) in drawnPaths {
            colour.setStroke()
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
        fillColour.usingColorSpace(.deviceRGB)?.getRed(&rF, green: &gF, blue: &bF, alpha: &aF)
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
        currentColour.setFill()

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
        } else if event.keyCode == 51 || event.keyCode == 117 { // Delete key
            deleteSelectionOrPastedImage()
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
        clearedOriginalAreaForCurrentSelection = false
    }

    private func beginScrollFreezeIfNeeded() {
        guard freezeClip == nil, let sv = enclosingScrollView else { return }
        let clip = sv.contentView
        freezeClip = clip
        freezeOrigin = clip.bounds.origin

        // Turn off rubber-banding while resizing so AppKit can't "helpfully" move us.
        savedElasticity = (sv.verticalScrollElasticity, sv.horizontalScrollElasticity)
        sv.verticalScrollElasticity   = .none
        sv.horizontalScrollElasticity = .none
    }

    private func maintainScrollFreeze() {
        guard let clip = freezeClip, let o = freezeOrigin else { return }

        // Clamp the stored origin to the current document extents.
        let doc = clip.documentRect
        let bw  = clip.bounds.size.width
        let bh  = clip.bounds.size.height

        // max() guards the case where document is smaller than the visible size.
        let maxX = max(0, doc.width  - bw)
        let maxY = max(0, doc.height - bh)

        var pinned = NSPoint(x: min(max(0, o.x), maxX),
                             y: min(max(0, o.y), maxY))

        // Only adjust if AppKit moved us.
        if pinned != clip.bounds.origin {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            clip.scroll(to: pinned)
            (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
            NSAnimationContext.endGrouping()
        }
    }

    private func endScrollFreeze() {
        if let sv = enclosingScrollView, let e = savedElasticity {
            sv.verticalScrollElasticity   = e.v
            sv.horizontalScrollElasticity = e.h
        }
        savedElasticity = nil
        freezeClip = nil
        freezeOrigin = nil
    }
    
    override func viewWillDraw() {
        super.viewWillDraw()
        // If AppKit adjusted after layout, pin it back before paint.
        //if isResizingCanvas { maintainScrollFreeze() }
    }
    
    func pointsAreEqual(_ p1: NSPoint, _ p2: NSPoint) -> Bool {
        return Int(p1.x) == Int(p2.x) && Int(p1.y) == Int(p2.y)
    }
    
    @objc public func moveSelectionBy(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else {
            emitStatusUpdate(cursor: mousePosition)
            return
        }
        
        // 1) If we’re nudging a pasted image, move the overlay AND the visible selection.
        if isPastingActive {
            // Prefer the selection origin (that’s what draw() uses), but fall back to the paste origin.
            let base = selectedImageOrigin ?? pastedImageOrigin
            if let origin = base {
                let newOrigin = NSPoint(x: origin.x + dx, y: origin.y + dy)
                selectedImageOrigin = newOrigin
                if let img = selectedImage {
                    selectionRect = NSRect(origin: newOrigin, size: img.size)
                }
                pastedImageOrigin = newOrigin
                needsDisplay = true
                emitStatusUpdate(cursor: mousePosition)
                return
            }
        }

        // 2) If we only have a marquee (no floating bitmap yet), CUT once and promote.
        if selectedImage == nil,
           let rect = selectionRect,
           rect.width > 0, rect.height > 0 {
            cutSelectionToFloatingIfNeeded() // sets clearedOriginalAreaForCurrentSelection & hasMovedSelection
        } else {
            // 3) If already floating, clear original area exactly once if not already done.
            ensureOriginalAreaClearedIfNeeded()
        }

        // 4) Nudge the floating selection (preferred) or, as fallback, the marquee.
        if let origin = selectedImageOrigin {
            let newOrigin = NSPoint(x: origin.x + dx, y: origin.y + dy)
            selectedImageOrigin = newOrigin
            if let img = selectedImage {
                selectionRect = NSRect(origin: newOrigin, size: img.size)
            }
            needsDisplay = true
        } else if let r = selectionRect {
            // Should rarely happen; kept for safety.
            selectionRect = r.offsetBy(dx: dx, dy: dy)
            needsDisplay = true
        }

        emitStatusUpdate(cursor: mousePosition)
    }
    
    /// Make all pixels that match `key` (within `tolerance`) transparent.
    func imageByMakingColorTransparent(_ image: NSImage,
                                       key: NSColor,
                                       tolerance: CGFloat = 0.0) -> NSImage? {
        guard let rep = image.rgba8Bitmap(), let data = rep.bitmapData else { return nil }

        // Normalize key to deviceRGB
        let k = (key.usingColorSpace(.deviceRGB) ?? key)
        let kr = UInt8(round(k.redComponent   * 255))
        let kg = UInt8(round(k.greenComponent * 255))
        let kb = UInt8(round(k.blueComponent  * 255))

        let w = rep.pixelsWide, h = rep.pixelsHigh
        let spp = rep.samplesPerPixel // 4
        let bpr = rep.bytesPerRow
        let tol = UInt8(max(0, min(255, Int(tolerance * 255))))

        func close(_ a: UInt8, _ b: UInt8) -> Bool {
            let d = a > b ? a - b : b - a
            return d <= tol
        }

        for y in 0..<h {
            let row = data.advanced(by: y * bpr)
            for x in 0..<w {
                let p = row.advanced(by: x * spp) // RGBA
                if close(p[0], kr) && close(p[1], kg) && close(p[2], kb) {
                    p[3] = 0 // transparent
                }
            }
        }
        let out = NSImage(size: image.size)
        out.addRepresentation(rep)
        return out
    }

    // The key method the rest of the code will call whenever the canvas needs to change size
    @discardableResult
    func updateCanvasSize(to newSize: NSSize) -> NSSize {
        // Keep the bitmap in sync with the logical canvas rect
        resizeBackingImage(to: newSize)

        // Update model + frame
        canvasRect.size = newSize
        setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)

        invalidateIntrinsicContentSize()
        needsDisplay = true
        return newSize
    }
    
    // MARK: - Image menu operations called by AppDelegate

    func applyFlipRotate(flipHorizontal: Bool, flipVertical: Bool, rotationDegrees: Int) {
        // Prefer active selection if present
        if var img = selectedImage {
            if flipHorizontal || flipVertical { img = img.flipped(horizontal: flipHorizontal, vertical: flipVertical) }
            if rotationDegrees % 360 != 0      { img = img.rotated(byDegrees: CGFloat(rotationDegrees)) }

            // Update selection buffers
            selectedImage = img
            if let origin = selectedImageOrigin {
                selectionRect = NSRect(origin: origin, size: img.size)
            }
            needsDisplay = true
            return
        }

        // Otherwise apply to entire canvas
        guard var base = canvasImage else { return }
        saveUndoState()
        if flipHorizontal || flipVertical {
            base = base.flipped(horizontal: flipHorizontal, vertical: flipVertical)
        }
        if rotationDegrees % 360 != 0 {
            base = base.rotated(byDegrees: CGFloat(rotationDegrees))
        }

        // ✅ Make result canonical & clear stale vectors so they can't reappear
        commitRasterChange(base, resetVectors: true)
    }

    func applyStretchSkew(scaleXPercent sx: Int, scaleYPercent sy: Int, skewXDegrees kx: Int, skewYDegrees ky: Int) {
        // Prefer active selection if present
        if var img = selectedImage {
            if sx != 100 || sy != 100 {
                img = img.scaled(byXPercent: CGFloat(sx), yPercent: CGFloat(sy))
            }
            if kx != 0 || ky != 0 {
                img = img.sheared(kxDegrees: CGFloat(kx), kyDegrees: CGFloat(ky))
            }

            selectedImage = img
            if let origin = selectedImageOrigin {
                selectionRect = NSRect(origin: origin, size: img.size)
            }
            needsDisplay = true
            return
        }

        // Otherwise apply to entire canvas
        guard var base = canvasImage else { return }
        saveUndoState()

        if sx != 100 || sy != 100 {
            base = base.scaled(byXPercent: CGFloat(sx), yPercent: CGFloat(sy))
        }
        if kx != 0 || ky != 0 {
            base = base.sheared(kxDegrees: CGFloat(kx), kyDegrees: CGFloat(ky))
        }

        // ✅ Bake it in & drop vector cache so floodFill/eyedropper can't resurrect old geometry
        commitRasterChange(base, resetVectors: true)
    }

    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .colourPicked, object: nil)
    }
}

// MARK: - Image transform helpers (CanvasView.swift)

extension NSImage {
    fileprivate var cgImageSafe: CGImage? {
        guard let tiff = self.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let cg   = rep.cgImage else { return nil }
        return cg
    }

    func rotated(byDegrees deg: CGFloat) -> NSImage {
        let radians = deg * .pi / 180
        let s = size
        let outSize: NSSize = (Int(deg) % 180 == 0) ? s : NSSize(width: s.height, height: s.width)

        let out = NSImage(size: outSize)
        out.lockFocus()

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: outSize.width/2, y: outSize.height/2)
        ctx.rotate(by: radians)

        let drawRect = NSRect(x: -s.width/2, y: -s.height/2, width: s.width, height: s.height)
        draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        out.unlockFocus()
        return out
    }

    func flipped(horizontal: Bool = false, vertical: Bool = false) -> NSImage {
        guard horizontal || vertical else { return self }
        let s = size
        let out = NSImage(size: s)
        out.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: horizontal ? s.width : 0, y: vertical ? s.height : 0)
        ctx.scaleBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
        draw(in: NSRect(origin: .zero, size: s), from: .zero, operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    func scaled(byXPercent px: CGFloat, yPercent py: CGFloat) -> NSImage {
        let sx = max(1, px) / 100.0
        let sy = max(1, py) / 100.0
        let newSize = NSSize(width: floor(size.width * sx), height: floor(size.height * sy))
        let out = NSImage(size: newSize)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .sourceOver,
             fraction: 1.0)
        out.unlockFocus()
        return out
    }

    func sheared(kxDegrees: CGFloat, kyDegrees: CGFloat) -> NSImage {
        let kx = tan(kxDegrees * .pi / 180)
        let ky = tan(kyDegrees * .pi / 180)
        let s = size
        let newW = s.width + abs(ky) * s.height
        let newH = s.height + abs(kx) * s.width
        let outSize = NSSize(width: ceil(newW), height: ceil(newH))

        let out = NSImage(size: outSize)
        out.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext

        // Leave space for the shear so we don’t clip
        ctx.translateBy(x: (ky < 0 ? abs(ky) * s.height / 2 : 0),
                        y: (kx < 0 ? abs(kx) * s.width  / 2 : 0))

        let t = CGAffineTransform(a: 1, b: ky, c: kx, d: 1, tx: 0, ty: 0)
        ctx.concatenate(t)

        draw(in: NSRect(origin: .zero, size: s), from: .zero, operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }
}


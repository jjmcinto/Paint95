import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func didPickColour(_ colour: NSColor)
    func canvasStatusDidChange(cursor: NSPoint, selectionSize: NSSize?)
}

// Add once somewhere in the file (e.g., near other helpers)
private extension NSRect {
    var isFiniteRect: Bool {
        return origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}
extension NSCursor {
    /// ↘︎↖︎ (NW–SE)
    static let resizeDiagonalNWSE: NSCursor = {
        if let img = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil) {
            img.size = NSSize(width: 18, height: 18)
            return NSCursor(image: img, hotSpot: NSPoint(x: 9, y: 9))
        }
        // Fallback: simple drawn diagonal
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let p = NSBezierPath()
        p.lineWidth = 2
        p.move(to: NSPoint(x: 2,  y: 14))
        p.line(to: NSPoint(x: 14, y: 2))
        p.stroke()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }()

    /// ↗︎↙︎ (NE–SW)
    static let resizeDiagonalNESW: NSCursor = {
        if let img = NSImage(systemSymbolName: "arrow.up.right.and.arrow.down.left", accessibilityDescription: nil) {
            img.size = NSSize(width: 18, height: 18)
            return NSCursor(image: img, hotSpot: NSPoint(x: 9, y: 9))
        }
        // Fallback: simple drawn diagonal
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let p = NSBezierPath()
        p.lineWidth = 2
        p.move(to: NSPoint(x: 2,  y: 2))
        p.line(to: NSPoint(x: 14, y: 14))
        p.stroke()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }()
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
    var control1Set = false
    var control2Set = false
    
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
    private let scrollGutter: CGFloat = 20 // How much extra scrollable space you want around the canvas
    private let edgeHitOutside: CGFloat = 8 // How far *outside* the canvas edge we still accept a resize click
    private let edgeHitInside:  CGFloat = 2 // How far *inside* the canvas edge we still accept a resize click (small, so you can still draw at edges)
    private let cornerHit: CGFloat = 12 // Approx square size for corner hot-zones (diagonal resize). Corners win over edges.
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
    private let borderHitWidth: CGFloat = 6
    
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
        let s = isZoomed ? zoomScale : 1.0
        let pad = resizeGutter * s * 2
        return NSSize(
            width:  canvasRect.width  * s + pad,
            height: canvasRect.height * s + pad
        )
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
            
            if currentTool == .curve {
                curvePhase = 0
                curveStart = .zero
                curveEnd   = .zero
                control1   = .zero
                control2   = .zero
                cancelCurvePreview = false
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
    private var freezeClip: NSClipView?
    private var freezeOrigin: NSPoint?
    private var savedPostsBounds: Bool?
    private var isFreezeActive: Bool { freezeClip != nil }
    private var isMaintainingScrollFreeze = false
    private var scrollFreezeObserver: NSObjectProtocol?
    private let resizeGutter: CGFloat = 8.0
    
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
        applyScrollGutters()
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
        let rImg = imgRect(rect)
        if lockFocus { canvasImage?.lockFocus() }
        NSColor.white.setFill()
        rImg.fill()
        if lockFocus { canvasImage?.unlockFocus() }

        // Paths are stored in image-space already
        drawnPaths.removeAll { $0.path.bounds.intersects(rImg) }
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

        // One rect to rule them all: where the canvas lives in *view* space.
        let canvasViewRect: NSRect = isZoomed ? toZoomed(canvasRect) : canvasRect

        // === Canvas image drawing ===
        if isResizingCanvas {
            if let image = canvasImage {
                image.draw(in: canvasViewRect,
                           from: NSRect(origin: .zero, size: canvasRect.size),
                           operation: .copy,
                           fraction: 1.0,
                           respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.none])
            }

            // Dashed live-preview of the canvas bounds (same rect)
            NSColor.red.setStroke()
            let dashPattern: [CGFloat] = [5.0, 3.0]
            let path = NSBezierPath(rect: canvasViewRect)
            path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            path.stroke()

        } else if isZoomed {
            guard let image = canvasImage else { return }

            // Draw the WHOLE canvas scaled at the same rect we’ll use for the border.
            image.draw(in: canvasViewRect,
                       from: NSRect(origin: .zero, size: canvasRect.size),
                       operation: .copy,
                       fraction: 1.0,
                       respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.none])

            // Single border—same rect, no duplicate 0,0 border anymore.
            NSColor.black.setStroke()
            NSBezierPath(rect: canvasViewRect).stroke()

        } else {
            // Not zoomed
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
                // Clip to the visible canvas in *view* space
                NSBezierPath(rect: canvasViewRect).addClip()
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
            var s = curveStart, e = curveEnd, c1 = control1, c2 = control2
            if isZoomed { s = toZoomed(s); e = toZoomed(e); c1 = toZoomed(c1); c2 = toZoomed(c2) }

            // Effective controls based on phase
            // - phase 0: show a straight line
            // - phase 1: use c1 for both handles (quadratic-like). If c1==s, it stays straight.
            // - phase 2: use c1 and c2; if user hasn’t moved c2 yet, treat c2 as `e` so only c1 bends.
            let c1Eff = (curvePhase >= 1) ? c1 : s
            let c2Eff = (curvePhase == 2) ? c2
                       : (curvePhase == 1 ? c1 : e)

            let path = NSBezierPath()
            path.lineWidth = toolSize * (isZoomed ? zoomScale : 1)
            currentColour.set()
            
            switch curvePhase {
            case 0:
                if s != e { path.move(to: s); path.line(to: e); path.stroke() }
            case 1:
                path.move(to: s)
                path.curve(to: e, controlPoint1: c1Eff, controlPoint2: c1Eff)
                path.stroke()
            case 2:
                path.move(to: s)
                path.curve(to: e, controlPoint1: c1Eff, controlPoint2: c2Eff)
                path.stroke()
            default:
                break
            }
            cancelCurvePreview = false
        }
 else if isDrawingShape {
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

        // === Canvas border when NOT zoomed ===
        if !isZoomed {
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
        
        let viewPt = convert(event.locationInWindow, from: nil)
        let point = convertZoomedPointToCanvas(viewPt)
        emitStatusUpdate(cursor: point)
        
        // Selection resize handles
        if let rect = selectionRect ?? (selectedImage != nil ? NSRect(origin: selectedImageOrigin ?? .zero, size: selectedImage!.size) : nil) {
            for (i, handle) in selectionHandlePositions(rect: rect).enumerated() {
                if handle.contains(point) {
                    saveUndoState()
                    activeSelectionHandle = SelectionHandle(rawValue: i)
                    isResizingSelection = true
                    resizeStartPoint = point
                    originalSelectionRect = rect
                    originalSelectedImage = selectedImage
                    return
                }
            }
        }

        // Points in both spaces
        let canvasPt = convertZoomedPointToCanvas(viewPt)
        
        // === Canvas border/corner detection (zoom- & gutter-safe) ===
        if let h = resizeHandle(at: point, generous: true) {
            saveUndoState()
            activeResizeHandle = h
            isResizingCanvas = true
            dragStartPoint = point
            initialCanvasRect = canvasRect
            beginScrollFreezeIfNeeded()
            return
        }

        // Commit paste if clicking outside it (unchanged)
        if isPastingImage,
           let img = selectedImage, let io = selectedImageOrigin {
            let activeRect = NSRect(origin: io, size: img.size)
            if !activeRect.contains(point) {
                commitSelection()
                isPastingImage = false
                isPastingActive = false
                pastedImage = nil
                pastedImageOrigin = nil
                // fall through
            }
        }

        initializeCanvasIfNeeded()

        switch currentTool {
        case .select:
            if let image = selectedImage, let io = selectedImageOrigin {
                let rect = NSRect(origin: io, size: image.size)
                if rect.contains(point) {
                    saveUndoState()
                    isDraggingSelection = true
                    selectionDragStartPoint = point
                    selectionImageStartOrigin = selectedImageOrigin
                    if !isPastingImage {
                        clearCanvasRegion(rect: rect)
                        clearedOriginalAreaForCurrentSelection = true
                        hasMovedSelection = true
                    }
                }
            } else if !isPastingImage {
                startPoint = point
                selectionRect = nil
                selectedImage = nil
                window?.makeFirstResponder(self)
            }
            
        case .spray:
            currentSprayPoint = convertZoomedPointToCanvas(viewPt)
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
            saveUndoState()
            startPoint = point
            currentPath = NSBezierPath()
            currentPath?.move(to: point)
            
        case .fill:
            saveUndoState()
            floodFill(from: point, with: currentColour)
            
        case .curve:
            if curvePhase == 0 {
                saveUndoState()
                curveStart = point
                curveEnd   = point
                startPoint = point
                endPoint   = point

                // Controls start at the endpoints → no bend until user moves them
                control1   = point   // equals start
                control2   = point   // will mirror in phase 1, or become end in phase 2
            }
            
        case .line, .rect, .roundRect, .ellipse:
            saveUndoState()
            startPoint = point
            endPoint = point
            isDrawingShape = true
            
        case .zoom:
            // If this click is on/near a border or corner, treat it as a resize instead of toggling zoom.
            if let h = resizeHandle(at: point, generous: true) {
                saveUndoState()
                activeResizeHandle = h
                isResizingCanvas = true
                dragStartPoint = point
                initialCanvasRect = canvasRect
                beginScrollFreezeIfNeeded()
                return
            }

            if isZoomed {
                // === Exit zoom (be defensive about scroll/clip state) ===
                isZoomed = false
                zoomScale = 1.0
                zoomPreviewRect = nil

                updateZoomDocumentSize()        // resets documentView size back to canvasRect.size
                constrainClipViewBoundsNow()    // clamp any weird clip origins AppKit might hold
                needsDisplay = true

            } else {
                // === Enter zoom ===
                let p  = convert(event.locationInWindow, from: nil)
                let zr = zoomPreviewRect ?? NSRect(x: p.x - 64, y: p.y - 64, width: 128, height: 128)

                // Use the scrollview’s visible size as our viewport
                let viewport = (enclosingScrollView?.contentView.bounds.size) ?? bounds.size

                // Uniform scale so zr * scale fits in viewport
                let sx = max(1, viewport.width  / max(1, zr.width))
                let sy = max(1, viewport.height / max(1, zr.height))
                let z  = min(sx, sy)

                zoomScale = (z.isFinite && z > 0) ? z : 1.0
                isZoomed  = true
                updateZoomDocumentSize()

                // Scroll so the zoomed preview rect is visible (safe)
                let zsafe  = zoomScale
                let target = NSRect(x: zr.origin.x * zsafe,
                                    y: zr.origin.y * zsafe,
                                    width:  zr.size.width  * zsafe,
                                    height: zr.size.height * zsafe)
                scrollToVisibleSafe(target)

                needsDisplay = true
            }

        }

        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let point  = convertZoomedPointToCanvas(viewPt)
        let shiftPressed = event.modifierFlags.contains(.shift)
        emitStatusUpdate(cursor: point)

        // Selection resizing (unchanged)
        if isResizingSelection, let handle = activeSelectionHandle {
            var newRect = originalSelectionRect
            let dx = point.x - resizeStartPoint.x
            let dy = point.y - resizeStartPoint.y
            switch handle {
            case .topLeft:     newRect.origin.x += dx; newRect.size.width -= dx; newRect.size.height += dy
            case .topCenter:   newRect.size.height += dy
            case .topRight:    newRect.size.width += dx; newRect.size.height += dy
            case .middleLeft:  newRect.origin.x += dx; newRect.size.width -= dx
            case .middleRight: newRect.size.width += dx
            case .bottomLeft:  newRect.origin.x += dx; newRect.size.width -= dx; newRect.origin.y += dy; newRect.size.height -= dy
            case .bottomCenter:newRect.origin.y += dy; newRect.size.height -= dy
            case .bottomRight: newRect.size.width += dx; newRect.origin.y += dy; newRect.size.height -= dy
            }
            if shiftPressed {
                let aspect = originalSelectionRect.width / max(originalSelectionRect.height, 1)
                if [.topLeft,.topRight,.bottomLeft,.bottomRight].contains(handle) {
                    let wsgn: CGFloat = newRect.width >= 0 ? 1 : -1
                    let hsgn: CGFloat = newRect.height >= 0 ? 1 : -1
                    if abs(newRect.width) > abs(newRect.height * aspect) {
                        newRect.size.height = abs(newRect.width) / aspect * hsgn
                    } else {
                        newRect.size.width  = abs(newRect.height * aspect) * wsgn
                    }
                }
            }
            if let image = originalSelectedImage {
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

        // Canvas resize preview (zoomed or not): keep scroll origin pinned on EVERY drag tick.
        if isResizingCanvas, let handle = activeResizeHandle {
            var newRect = initialCanvasRect
            let dx = point.x - dragStartPoint.x
            let dy = point.y - dragStartPoint.y

            switch handle {
            case .bottomLeft:
                newRect.origin.x += dx; newRect.origin.y += dy
                newRect.size.width  -= dx; newRect.size.height -= dy
            case .bottomCenter:
                newRect.origin.y += dy; newRect.size.height -= dy
            case .bottomRight:
                newRect.origin.y += dy; newRect.size.height -= dy; newRect.size.width += dx
            case .middleLeft:
                newRect.origin.x += dx; newRect.size.width  -= dx
            case .middleRight:
                newRect.size.width += dx
            case .topLeft:
                newRect.origin.x += dx; newRect.size.width  -= dx; newRect.size.height += dy
            case .topCenter:
                newRect.size.height += dy
            case .topRight:
                newRect.size.width  += dx; newRect.size.height += dy
            }

            // Min size while keeping opposite edge anchored
            if newRect.width < 50 {
                switch handle { case .bottomLeft, .middleLeft, .topLeft: newRect.origin.x = initialCanvasRect.maxX - 50; default: break }
                newRect.size.width = 50
            }
            if newRect.height < 50 {
                switch handle { case .bottomLeft, .bottomCenter, .bottomRight: newRect.origin.y = initialCanvasRect.maxY - 50; default: break }
                newRect.size.height = 50
            }

            // PREVIEW ONLY (no frame/ICS churn)
            canvasRect = newRect
            needsDisplay = true

            // 🔒 keep scrollbars frozen while dragging
            maintainScrollFreeze()

            return
        }

        // Dragging selection (unchanged)
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

        // Tools (unchanged behaviour)
        switch currentTool {
        case .select:
            if !isPastingImage {
                endPoint = point
                selectionRect = rectBetween(startPoint, and: endPoint)
                needsDisplay = true
            }
        case .spray:
            currentSprayPoint = convertZoomedPointToCanvas(viewPt)
        case .text:
            if isCreatingText {
                textBoxRect = rectBetween(startPoint, and: point)
                needsDisplay = true
            }
        case .pencil, .brush:
            currentPath?.line(to: point)
            drawCurrentPathToCanvas()
            currentPath = NSBezierPath(); currentPath?.move(to: point)
        case .eraser:
            currentPath?.line(to: point)
            drawCurrentPathToCanvas()
            eraseDot(at: point)
            currentPath = NSBezierPath(); currentPath?.move(to: point)
        case .line, .rect, .roundRect, .ellipse:
            endPoint = point
            if shiftPressed {
                let dx = endPoint.x - startPoint.x
                let dy = endPoint.y - startPoint.y
                switch currentTool {
                case .line:
                    let angle = atan2(dy, dx)
                    let snap = round(angle / (.pi / 4)) * (.pi / 4)
                    let length = hypot(dx, dy)
                    endPoint = NSPoint(x: startPoint.x + cos(snap) * length,
                                       y: startPoint.y + sin(snap) * length)
                case .rect, .roundRect, .ellipse:
                    let size = max(abs(dx), abs(dy))
                    endPoint.x = startPoint.x + (dx >= 0 ? size : -size)
                    endPoint.y = startPoint.y + (dy >= 0 ? size : -size)
                default: break
                }
            }
            needsDisplay = true
        case .curve:
            switch curvePhase {
            case 0: curveEnd  = point
            case 1: control1  = point
            case 2: control2  = point
            default: break
            }
            needsDisplay = true
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if currentTool != .zoom { zoomPreviewRect = nil }

        if isResizingCanvas {
            isResizingCanvas = false
            let handleUsed = activeResizeHandle
            cropCanvasImageToCanvasRect(using: handleUsed)  // commits + syncs frame/ICS
            activeResizeHandle = nil

            // Stop freezing BEFORE any deferred scrolling we do next.
            endScrollFreeze()

            // Optional: after commit, keep the anchor corner visible
            if let sv = enclosingScrollView {
                DispatchQueue.main.async { [weak self, weak sv] in
                    guard let self = self, let _ = sv else { return }

                    let w = self.canvasRect.width
                    let h = self.canvasRect.height

                    // Choose the anchor in *canvas* coords
                    let canvasAnchor: NSRect
                    switch handleUsed {
                    case .topRight?:     canvasAnchor = NSRect(x: w - 1, y: h - 1, width: 1, height: 1)
                    case .topCenter?:    canvasAnchor = NSRect(x: w / 2,  y: h - 1, width: 1, height: 1)
                    case .middleRight?:  canvasAnchor = NSRect(x: w - 1,  y: h / 2, width: 1, height: 1)
                    case .topLeft?:      canvasAnchor = NSRect(x: 1,      y: h - 1, width: 1, height: 1)
                    case .bottomRight?:  canvasAnchor = NSRect(x: w - 1,  y: 1,      width: 1, height: 1)
                    case .bottomCenter?: canvasAnchor = NSRect(x: w / 2,  y: 1,      width: 1, height: 1)
                    case .middleLeft?:   canvasAnchor = NSRect(x: 1,      y: h / 2,  width: 1, height: 1)
                    case .bottomLeft?:   fallthrough
                    default:             canvasAnchor = NSRect(x: 0,      y: 0,      width: 1, height: 1)
                    }

                    // Convert to *view* coords if zoomed
                    let target: NSRect
                    if self.isZoomed {
                        target = NSRect(x: canvasAnchor.origin.x * self.zoomScale,
                                        y: canvasAnchor.origin.y * self.zoomScale,
                                        width:  canvasAnchor.size.width  * self.zoomScale,
                                        height: canvasAnchor.size.height * self.zoomScale)
                    } else {
                        target = canvasAnchor
                    }

                    self.scrollToVisibleSafe(target)
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

        let pt = convertZoomedPointToCanvas(convert(event.locationInWindow, from: nil))
        let shiftPressed = event.modifierFlags.contains(.shift)
        emitStatusUpdate(cursor: pt)

        if let image = selectedImage, let io = selectedImageOrigin {
            let rect = NSRect(origin: io, size: image.size)
            if !rect.contains(pt) {
                commitSelection()
                return
            }
        }

        if isPastingImage, let image = selectedImage, let io = selectedImageOrigin {
            let frame = NSRect(origin: io, size: image.size)
            if !frame.contains(pt) {
                commitSelection()
                isPastingImage = false
                isPastingActive = false
                needsDisplay = true
                return
            }
        }

        endPoint = pt

        switch currentTool {
        case .select:
            guard let rect = selectionRect else { return }
            let src = imgRect(rect)

            let image = NSImage(size: rect.size)
            image.lockFocus()
            canvasImage?.draw(in: NSRect(origin: .zero, size: rect.size),
                              from: src,
                              operation: .copy,
                              fraction: 1.0,
                              respectFlipped: true,
                              hints: [.interpolation: NSImageInterpolation.none])
            image.unlockFocus()

            selectedImage = image
            selectedImageOrigin = rect.origin
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
                NSRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1).fill()
                canvasImage?.unlockFocus()
                needsDisplay = true
            }
            currentPath = nil

        case .brush:
            if pointsAreEqual(startPoint, endPoint) {
                initializeCanvasIfNeeded()
                canvasImage?.lockFocus()
                currentColour.set()
                let b = max(1, toolSize)
                let dot = NSRect(x: startPoint.x - b/2, y: startPoint.y - b/2, width: b, height: b)
                NSBezierPath(ovalIn: dot).fill()
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
                NSRect(x: startPoint.x, y: startPoint.y, width: 1, height: 1).fill()
                canvasImage?.unlockFocus()
            } else {
                endPoint = finalEnd
                drawShape(to: canvasImage)
            }
            isDrawingShape = false
            needsDisplay = true

        case .curve:
            // mouseUp(with:), case .curve
            switch curvePhase {
            case 0:
                curvePhase = 1

            case 1:
                control1 = pt
                control2 = control1
                curvePhase = 2

            case 2:
                control2 = pt

                // Same effective logic as preview
                let c1Eff = control1
                let c2Eff = (pointsAreEqual(control2, curveEnd) ? curveEnd : control2)

                let path = NSBezierPath()
                path.move(to: curveStart)
                path.curve(to: curveEnd, controlPoint1: c1Eff, controlPoint2: c2Eff)
                path.lineWidth = toolSize

                let translated = path.copy() as! NSBezierPath
                let t = AffineTransform(translationByX: -canvasRect.origin.x, byY: -canvasRect.origin.y)
                translated.transform(using: t)

                canvasImage?.lockFocus()
                currentColour.set()
                translated.stroke()
                canvasImage?.unlockFocus()
                drawnPaths.append((path: translated.copy() as! NSBezierPath, colour: currentColour))

                // Reset curve state
                curvePhase = 0
                curveStart = .zero; curveEnd = .zero
                control1 = .zero;   control2 = .zero
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
        
        if event.keyCode == 53 /* ESC */ && currentTool == .curve {
            curvePhase = 0
            curveStart = .zero
            curveEnd   = .zero
            control1   = .zero
            control2   = .zero
            cancelCurvePreview = true
            needsDisplay = true
            return
        }

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
        guard selectedImage == nil,
              let rect = selectionRect,
              let base = canvasImage,
              rect.width > 0, rect.height > 0 else { return }

        let src = imgRect(rect)

        // Copy out to floating bitmap
        let img = NSImage(size: rect.size)
        img.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: rect.size),
                  from: src,
                  operation: .copy,
                  fraction: 1.0,
                  respectFlipped: true,
                  hints: [.interpolation: NSImageInterpolation.none])
        img.unlockFocus()
        selectedImage = img

        // Clear original area on base
        base.lockFocus()
        NSColor.white.setFill()
        src.fill()
        base.unlockFocus()

        clearedOriginalAreaForCurrentSelection = true
        hasMovedSelection = true
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

        let imageRect = NSRect(origin: origin, size: image.size)      // view-space
        let intersection = imageRect.intersection(canvasRect)          // view-space

        guard !intersection.isEmpty else {
            selectedImage = nil
            selectedImageOrigin = nil
            selectionRect = nil
            clearedOriginalAreaForCurrentSelection = false
            hasMovedSelection = false
            needsDisplay = true
            return
        }

        // Source (inside the selection bitmap)
        let srcInSelection = NSRect(
            origin: NSPoint(x: intersection.origin.x - origin.x,
                            y: intersection.origin.y - origin.y),
            size: intersection.size
        )

        // Destination (inside canvasImage, i.e. image-space)
        let destInImageOrigin = imgPoint(intersection.origin)
        let destInImageRect   = NSRect(origin: destInImageOrigin, size: intersection.size)

        initializeCanvasIfNeeded()
        canvasImage?.lockFocus()
        image.draw(in: destInImageRect,
                   from: srcInSelection,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.none])
        canvasImage?.unlockFocus()

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
    
    @objc func redo() {
        guard let next = redoStack.popLast() else { return }
        let current = CanvasSnapshot(image: canvasImage?.copy() as? NSImage, rect: canvasRect)
        undoStack.append(current)
        applySnapshot(next)
    }
    
    // Replace your current applySnapshot with this version
    private func applySnapshot(_ snap: CanvasSnapshot) {
        // 1) Restore pixels + logical size
        canvasImage = snap.image?.copy() as? NSImage
        let size    = snap.rect.size

        // 2) Keep the canvas inside the gutter (don’t leave origin at 0,0)
        canvasRect.origin = NSPoint(x: resizeGutter, y: resizeGutter)
        canvasRect.size   = size

        // 3) Size the documentView including gutter and zoom
        let s   = isZoomed ? zoomScaleSafe : 1.0
        let pad = resizeGutter * s * 2
        let frameSize = NSSize(width:  floor(size.width  * s) + pad,
                               height: floor(size.height * s) + pad)
        setFrameSize(frameSize)

        // 4) Normal invalidations
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
        applyScrollGutters()

        // 5) Clamp the clip view now that the documentView size changed
        constrainClipViewBoundsNow()

        // 6) Reset transient preview state
        curvePhase = 0
        curveStart = .zero
        curveEnd   = .zero
        control1   = .zero
        control2   = .zero
        cancelCurvePreview = false
        zoomPreviewRect = nil

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
            applyScrollGutters()
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

        // Re-calibrate model/view to keep the canvas INSIDE a gutter ring
        canvasRect.origin = NSPoint(x: resizeGutter, y: resizeGutter)
        canvasRect.size   = newSize

        // Size the documentView including gutter, and respect zoom
        let s   = isZoomed ? zoomScaleSafe : 1.0
        let pad = resizeGutter * s * 2
        let frameSize = NSSize(width:  floor(newSize.width  * s) + pad,
                               height: floor(newSize.height * s) + pad)
        setFrameSize(frameSize)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
        applyScrollGutters()
        needsDisplay = true
    }
    
    // MARK: - Uniform zoom helpers (1:1 pixel aspect with letterboxing)
    private func updateZoomDocumentSize() {
        let s   = isZoomed ? zoomScaleSafe : 1.0
        let pad = resizeGutter * s * 2
        let size = NSSize(width:  max(1, floor(canvasRect.width  * s)) + pad,
                          height: max(1, floor(canvasRect.height * s)) + pad)
        setFrameSize(size)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
        applyScrollGutters()
    }
    
    @inline(__always)
    private func imgPoint(_ p: NSPoint) -> NSPoint {
        NSPoint(x: p.x - canvasRect.origin.x, y: p.y - canvasRect.origin.y)
    }

    @inline(__always)
    private func imgRect(_ r: NSRect) -> NSRect {
        NSRect(x: r.origin.x - canvasRect.origin.x,
               y: r.origin.y - canvasRect.origin.y,
               width: r.size.width,
               height: r.size.height)
    }
    
    private func zoomScaleAndOffset() -> (scale: CGFloat, offset: NSPoint) {
        let s = min(canvasRect.width / zoomRect.width,
                    canvasRect.height / zoomRect.height)
        let ox = (canvasRect.width  - zoomRect.width  * s) * 0.5
        let oy = (canvasRect.height - zoomRect.height * s) * 0.5
        return (s, NSPoint(x: ox, y: oy))
    }

    private func toZoomed(_ p: NSPoint) -> NSPoint {
        guard isZoomed else { return p }
        let z = zoomScaleSafe
        return .init(x: p.x * z, y: p.y * z)
    }
    
    private func toZoomed(_ r: NSRect) -> NSRect {
        guard isZoomed else { return r }
        let z = zoomScaleSafe
        return .init(x: r.origin.x * z, y: r.origin.y * z,
                     width: r.size.width * z, height: r.size.height * z)
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
    
    // Hit-test for canvas border/corners in VIEW coordinates (works with zoom + gutters).
    private func resizeHandleHit(atViewPoint p: NSPoint) -> ResizeHandle? {
        // Canvas border rect in VIEW space
        let rV: NSRect = isZoomed
            ? NSRect(x: 0, y: 0,
                     width:  canvasRect.width  * zoomScale,
                     height: canvasRect.height * zoomScale)
            : canvasRect

        // Only react if we're inside the border "ring"
        let inner = rV.insetBy(dx:  borderHitWidth, dy:  borderHitWidth)
        let outer = rV.insetBy(dx: -borderHitWidth, dy: -borderHitWidth)
        guard outer.contains(p), !inner.contains(p) else { return nil }

        // Prefer corners first (diagonal resize)
        let s = borderHitWidth * 2
        let tl = NSRect(x: rV.minX - borderHitWidth, y: rV.maxY - borderHitWidth, width: s, height: s)
        let tc = NSRect(x: rV.midX - borderHitWidth, y: rV.maxY - borderHitWidth, width: s, height: s)
        let tr = NSRect(x: rV.maxX - borderHitWidth, y: rV.maxY - borderHitWidth, width: s, height: s)
        let ml = NSRect(x: rV.minX - borderHitWidth, y: rV.midY - borderHitWidth, width: s, height: s)
        let mr = NSRect(x: rV.maxX - borderHitWidth, y: rV.midY - borderHitWidth, width: s, height: s)
        let bl = NSRect(x: rV.minX - borderHitWidth, y: rV.minY - borderHitWidth, width: s, height: s)
        let bc = NSRect(x: rV.midX - borderHitWidth, y: rV.minY - borderHitWidth, width: s, height: s)
        let br = NSRect(x: rV.maxX - borderHitWidth, y: rV.minY - borderHitWidth, width: s, height: s)

        if tl.contains(p) { return .topLeft }
        if tr.contains(p) { return .topRight }
        if bl.contains(p) { return .bottomLeft }
        if br.contains(p) { return .bottomRight }

        if tc.contains(p) { return .topCenter }
        if bc.contains(p) { return .bottomCenter }
        if ml.contains(p) { return .middleLeft }
        if mr.contains(p) { return .middleRight }

        return nil
    }

    // Returns which resize handle was hit, using an OUTSIDE ring around `canvasRect`.
    /// Hit-test for canvas resize. When `generous` is true we expand the bands so
    /// zoom-clicks near the edge are treated as resize gestures instead of toggling zoom.
    private func resizeHandle(at p: NSPoint, generous: Bool = false) -> ResizeHandle? {
        let r = canvasRect
        let z = zoomScaleSafe

        // Visual sizes (constant to the eye), converted to canvas space.
        let edgeV: CGFloat    = generous ? 14 : 8      // edge band thickness (view px)
        let cornerV: CGFloat  = generous ? 24 : 16     // corner square (view px)
        let edge  = isZoomed ? max(1, edgeV   / z) : edgeV
        let corner = isZoomed ? max(1, cornerV / z) : cornerV

        // Keep the exact border free for drawing. Epsilon moves the bands strictly outside.
        let eps: CGFloat = isZoomed ? max(0.5 / z, 0.25) : 0.5

        // --- Corners OUTSIDE the canvas (four little squares just beyond each corner) ---
        // TL: left of minX and above maxY
        let tl = NSRect(x: r.minX - corner, y: r.maxY + eps, width: corner, height: corner)
        if tl.contains(p) { return .topLeft }

        // TR: right of maxX and above maxY
        let tr = NSRect(x: r.maxX + eps, y: r.maxY + eps, width: corner, height: corner)
        if tr.contains(p) { return .topRight }

        // BL: left of minX and below minY
        let bl = NSRect(x: r.minX - corner, y: r.minY - corner - eps, width: corner, height: corner)
        if bl.contains(p) { return .bottomLeft }

        // BR: right of maxX and below minY
        let br = NSRect(x: r.maxX + eps, y: r.minY - corner - eps, width: corner, height: corner)
        if br.contains(p) { return .bottomRight }

        // --- Edge bands OUTSIDE the canvas (avoid corners by insetting with corner*0.5) ---
        // Top band just above the canvas
        let top = NSRect(x: r.minX + corner * 0.5,
                         y: r.maxY + eps,
                         width: max(0, r.width - corner),
                         height: edge)
        if top.contains(p) { return .topCenter }

        // Bottom band just below the canvas
        let bottom = NSRect(x: r.minX + corner * 0.5,
                            y: r.minY - edge - eps,
                            width: max(0, r.width - corner),
                            height: edge)
        if bottom.contains(p) { return .bottomCenter }

        // Left band just left of the canvas
        let left = NSRect(x: r.minX - edge - eps,
                          y: r.minY + corner * 0.5,
                          width: edge,
                          height: max(0, r.height - corner))
        if left.contains(p) { return .middleLeft }

        // Right band just right of the canvas
        let right = NSRect(x: r.maxX + eps,
                           y: r.minY + corner * 0.5,
                           width: edge,
                           height: max(0, r.height - corner))
        if right.contains(p) { return .middleRight }

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
    
    // MARK: Diagonal resize cursors (fallbacks if images aren’t available)
    private var diagonalNWSECursor: NSCursor {
        let p = "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northWestSouthEastResizeCursor.png"
        if FileManager.default.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) {
            return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
        }
        return .crosshair // sensible fallback
    }

    private var diagonalNESWCursor: NSCursor {
        let p = "/System/Library/Frameworks/WebKit.framework/Versions/Current/Frameworks/WebCore.framework/Resources/northEastSouthWestResizeCursor.png"
        if FileManager.default.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) {
            return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
        }
        return .crosshair // sensible fallback
    }
    
    // MARK: - Safety helpers
    private var zoomScaleSafe: CGFloat {
        let z = zoomScale
        return (z.isFinite && z > 0) ? z : 1.0
    }

    @inline(__always)
    private func isFinite(_ r: NSRect) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite && r.size.width.isFinite && r.size.height.isFinite
    }

    private func scrollToVisibleSafe(_ rect: NSRect) {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite else { return }
        scrollToVisible(rect)
    }
    
    private func constrainClipViewBoundsNow() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let constrained = clip.constrainBoundsRect(clip.bounds).origin
        guard constrained.x.isFinite, constrained.y.isFinite else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            clip.setBoundsOrigin(constrained)
            (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
        }
    }

    private func addCursorRectIfFinite(_ r: NSRect, cursor: NSCursor) {
        guard r.isFiniteRect, !r.isNull, !r.isEmpty else { return }
        let clipped = r.intersection(bounds)
        guard clipped.isFiniteRect, !clipped.isNull, !clipped.isEmpty else { return }
        addCursorRect(clipped, cursor: cursor)
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()

        guard canvasRect.width.isFinite, canvasRect.height.isFinite,
              canvasRect.width > 0, canvasRect.height > 0,
              bounds.isFiniteRect, !bounds.isEmpty else { return }

        let s: CGFloat = (isZoomed && zoomScale.isFinite && zoomScale > 0) ? zoomScale : 1.0
        let r = canvasRect

        // Visual sizes in VIEW pixels
        let cornerV: CGFloat = 16
        let edgeV: CGFloat   = 8
        let epsV: CGFloat    = 0.5    // keeps exact border free for drawing

        // Canvas rect in VIEW space
        let minX = r.minX * s, maxX = r.maxX * s
        let minY = r.minY * s, maxY = r.maxY * s
        let widthV  = r.width  * s
        let heightV = r.height * s

        // --- Corner squares OUTSIDE the canvas ---
        let tl = NSRect(x: minX - cornerV, y: maxY + epsV,          width: cornerV, height: cornerV)
        let tr = NSRect(x: maxX + epsV,     y: maxY + epsV,          width: cornerV, height: cornerV)
        let bl = NSRect(x: minX - cornerV, y: minY - cornerV - epsV, width: cornerV, height: cornerV)
        let br = NSRect(x: maxX + epsV,     y: minY - cornerV - epsV, width: cornerV, height: cornerV)

        // --- Edge bands OUTSIDE the canvas (avoid corner zones with cornerV*0.5 inset) ---
        let top    = NSRect(x: minX + cornerV * 0.5, y: maxY + epsV,           width: widthV  - cornerV, height: edgeV)
        let bottom = NSRect(x: minX + cornerV * 0.5, y: minY - edgeV - epsV,   width: widthV  - cornerV, height: edgeV)
        let left   = NSRect(x: minX - edgeV - epsV,  y: minY + cornerV * 0.5,  width: edgeV,             height: heightV - cornerV)
        let right  = NSRect(x: maxX + epsV,          y: minY + cornerV * 0.5,  width: edgeV,             height: heightV - cornerV)

        // Diagonals (your custom cursors)
        addCursorRectIfFinite(tl.intersection(bounds), cursor: .resizeDiagonalNWSE) // top-left  ↘︎↖︎
        addCursorRectIfFinite(tr.intersection(bounds), cursor: .resizeDiagonalNESW) // top-right ↗︎↙︎
        addCursorRectIfFinite(bl.intersection(bounds), cursor: .resizeDiagonalNESW) // bottom-left ↗︎↙︎
        addCursorRectIfFinite(br.intersection(bounds), cursor: .resizeDiagonalNWSE) // bottom-right ↘︎↖︎

        // Edges
        addCursorRectIfFinite(top.intersection(bounds),    cursor: .resizeUpDown)
        addCursorRectIfFinite(bottom.intersection(bounds), cursor: .resizeUpDown)
        addCursorRectIfFinite(left.intersection(bounds),   cursor: .resizeLeftRight)
        addCursorRectIfFinite(right.intersection(bounds),  cursor: .resizeLeftRight)

        // --- Selection handles unchanged ---
        if let selectionFrame = (selectedImage != nil
            ? NSRect(origin: selectedImageOrigin ?? .zero, size: selectedImage!.size)
            : selectionRect) {

            let handles = selectionHandlePositions(rect: selectionFrame)
            for (i, r0) in handles.enumerated() {
                let scaled = isZoomed
                    ? NSRect(x: r0.origin.x * s, y: r0.origin.y * s, width: r0.size.width * s, height: r0.size.height * s)
                    : r0

                let cursor: NSCursor = {
                    switch i {
                    case 1, 6: return .resizeUpDown
                    case 3, 4: return .resizeLeftRight
                    case 0, 7: return .resizeDiagonalNWSE   // top-left & bottom-right
                    case 2, 5: return .resizeDiagonalNESW   // top-right & bottom-left
                    default:   return .arrow
                    }
                }()
                addCursorRectIfFinite(scaled.intersection(bounds), cursor: cursor)
            }
        }
    }

    
    private func cursorForHandle(index: Int) -> NSCursor {
        switch index {
        case 1, 6: return .resizeUpDown
        case 3, 4: return .resizeLeftRight
        case 5, 2: return .resizeDiagonalNWSE   // top-left & bottom-right
        case 7, 0: return .resizeDiagonalNESW   // top-right & bottom-left
        default:   return .arrow
        }
    }
    
    private func selectionCursorForHandle(index: Int) -> NSCursor {
        switch index {
        case 1, 6: return .resizeUpDown
        case 3, 4: return .resizeLeftRight
        case 0, 7: return .resizeDiagonalNWSE   // top-left & bottom-right
        case 2, 5: return .resizeDiagonalNESW   // top-right & bottom-left
        default:   return .arrow
        }
    }
    
    // View (scaled) → canvas (unscaled)
    func convertZoomedPointToCanvas(_ point: NSPoint) -> NSPoint {
        guard isZoomed else { return point }
        let z = zoomScaleSafe
        return NSPoint(x: point.x / z, y: point.y / z)
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
    
    /// Apply 20 px gutters around the document so you can scroll a bit past the edges.
    private func applyScrollGutters() {
        guard let sv = enclosingScrollView else { return }

        // Disable automatic adjustments so our insets stay exactly as we set them
        if #available(macOS 11.0, *) {
            sv.automaticallyAdjustsContentInsets = false
        }

        let insets = NSEdgeInsets(top: scrollGutter, left: scrollGutter,
                                  bottom: scrollGutter, right: scrollGutter)

        // Set on both the scroll view and its clip view to keep math consistent
        sv.contentInsets = insets
        sv.contentView.contentInsets = insets
    }
    
    // Start freezing the scroll position until we finish resizing.
    private func beginScrollFreezeIfNeeded() {
        guard freezeClip == nil, let sv = enclosingScrollView else { return }
        let clip = sv.contentView

        freezeClip = clip
        freezeOrigin = clip.bounds.origin

        // Record & enable bounds notifications so we can snap back immediately.
        savedPostsBounds = clip.postsBoundsChangedNotifications
        clip.postsBoundsChangedNotifications = true

        // Kill bounce that can re-nudge the origin mid-resize.
        if savedElasticity == nil {
            savedElasticity = (sv.verticalScrollElasticity, sv.horizontalScrollElasticity)
        }
        sv.verticalScrollElasticity = .none
        sv.horizontalScrollElasticity = .none

        // Observe origin changes and snap back.
        scrollFreezeObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { [weak self] _ in
            self?.maintainScrollFreeze()
        }

        // Apply once immediately.
        maintainScrollFreeze()
    }

    private func maintainScrollFreeze() {
        // Avoid re-entrancy if boundsDidChange fires again while we’re snapping back.
        if isMaintainingScrollFreeze { return }
        guard let clip = freezeClip, let o = freezeOrigin else { return }

        // If the clip got detached (e.g., view hierarchy changed), stop freezing.
        guard clip.window != nil, clip.superview != nil else {
            endScrollFreeze()
            return
        }

        isMaintainingScrollFreeze = true
        defer { isMaintainingScrollFreeze = false }

        var desired = clip.bounds
        desired.origin = o
        let constrainedOrigin = clip.constrainBoundsRect(desired).origin
        guard constrainedOrigin != clip.bounds.origin else { return }

        // Use scroll(to:) + reflectScrolledClipView; do it with zero-duration to avoid layout ripple.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            clip.scroll(to: constrainedOrigin)
            (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
        }
    }

    private func endScrollFreeze() {
        if let obs = scrollFreezeObserver {
            NotificationCenter.default.removeObserver(obs)
            scrollFreezeObserver = nil
        }

        if let sv = enclosingScrollView, let e = savedElasticity {
            sv.verticalScrollElasticity = e.v
            sv.horizontalScrollElasticity = e.h
        }
        savedElasticity = nil

        if let clip = freezeClip, let saved = savedPostsBounds {
            clip.postsBoundsChangedNotifications = saved
        }
        savedPostsBounds = nil

        freezeClip = nil
        freezeOrigin = nil
        isMaintainingScrollFreeze = false
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

        // Put the drawable canvas inside an outer gutter, so clicks outside can resize.
        canvasRect.origin = NSPoint(x: resizeGutter, y: resizeGutter)
        canvasRect.size   = newSize

        // Size the document view to include the gutter (and scale when zoomed).
        let s   = isZoomed ? zoomScale : 1.0
        let pad = resizeGutter * s * 2
        let frameSize = NSSize(
            width:  floor(newSize.width  * s) + pad,
            height: floor(newSize.height * s) + pad
        )

        setFrameSize(frameSize)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
        applyScrollGutters()
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


// ViewController.swift
import Cocoa

class ViewController: NSViewController, ToolbarDelegate, ColourPaletteDelegate, CanvasViewDelegate, ToolSizeSelectorDelegate {
    
    @IBOutlet weak var canvasView: CanvasView!
    @IBOutlet weak var toolbarView: ToolbarView!
    @IBOutlet weak var colourPaletteView: ColourPaletteView!
    @IBOutlet weak var colourSwatchView: ColourSwatchView!
    
    // Layout constants
    private let kPaletteHeight: CGFloat   = 80
    private let kStripHeight: CGFloat     = 24
    private let kGapSigToPalette: CGFloat = 4
    private let kGapPaletteToStrip: CGFloat = 6
    private let kGapStripToStatus: CGFloat  = 6
    
    // Runtime UI we add with Auto Layout
    private var statusBarField: NSTextField!
    private var signatureLabel: NSTextField!
    private var toolSizeSelectorView: ToolSizeSelectorView!
    private var canvasScrollView: NSScrollView?
    private var didEmbedCanvasInScroll = false
    private var colourWindowController: ColourSelectionWindowController?
    
    // NEW: fixed left column so the toolbar can’t move
    private var leftColumn: NSView!
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .colourPicked, object: nil)
        print("ViewController deinitialized")
    }
    
    // MARK: - Outlet sanity check
    func verifyOutlets(tag: String) -> Bool {
        var ok = true
        if canvasView == nil { print("[\(tag)] ❌ canvasView outlet is nil"); ok = false }
        if toolbarView == nil { print("[\(tag)] ❌ toolbarView outlet is nil"); ok = false }
        if colourPaletteView == nil { print("[\(tag)] ❌ colourPaletteView outlet is nil"); ok = false }
        if colourSwatchView == nil { print("[\(tag)] ❌ colourSwatchView outlet is nil"); ok = false }
        if ok { print("[\(tag)] ✅ All outlets non-nil") }
        return ok
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        guard verifyOutlets(tag: "viewDidLoad") else { return }
        
        toolbarView.delegate = self
        colourPaletteView.delegate = self
        canvasView.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateColourSwatch(_:)), name: .colourPicked, object: nil)
        
        // 0) Create a fixed left column and move toolbox + swatch into it
        buildLeftColumnAndReparentLeftControls()
        
        // 1) Status bar FIRST
        setupStatusBar()
        
        // 2) Embed canvas + signature
        embedCanvasIfNeeded()
        
        // 3) Palette between signature and status
        placePaletteBetweenSignatureAndStatus()
        
        // 4) Size strip to the right of the palette
        placeToolSizeStripRightOfPalette()
        
        // Swatch click -> colour dialog
        colourSwatchView.colour = canvasView.currentColour
        colourSwatchView.onClick = { [weak self] in self?.presentColourSelection() }
        
        // Keyboard routing
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleGlobalKeyDown(event)
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        if let win = self.view.window {
            win.styleMask.insert(.resizable)
            win.contentMinSize = NSSize(width: 700, height: 500)
            win.contentMaxSize = NSSize(width: 12000, height: 9000)
            win.resizeIncrements = NSSize(width: 1, height: 1)
            win.minSize = NSSize(width: 640, height: 480)
            win.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                 height: CGFloat.greatestFiniteMagnitude)
        }
    }
    
    // Keep controls above scroll content
    override func viewDidLayout() {
        super.viewDidLayout()
        if let scroll = canvasScrollView {
            view.addSubview(colourPaletteView, positioned: .above, relativeTo: scroll)
            if let strip = toolSizeSelectorView {
                view.addSubview(strip, positioned: .above, relativeTo: scroll)
            }
        }
    }
    
    // MARK: - Left column (TOOLBOX + SWATCH)
    
    private func buildLeftColumnAndReparentLeftControls() {
        // Make sure IB views are AL-friendly before we move them
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        colourSwatchView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create column
        let col = NSView()
        col.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(col)
        self.leftColumn = col
        
        // Column pinned to window edges (left+top+bottom), fixed width (use swatch width: 101)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            col.topAnchor.constraint(equalTo: view.topAnchor),
            col.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            col.widthAnchor.constraint(equalToConstant: 101)
        ])
        
        // Reparent toolbox + swatch
        toolbarView.removeFromSuperview()
        colourSwatchView.removeFromSuperview()
        col.addSubview(toolbarView)
        col.addSubview(colourSwatchView)
        
        // Toolbox at top, full width of column
        NSLayoutConstraint.activate([
            toolbarView.leadingAnchor.constraint(equalTo: col.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: col.trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: col.topAnchor, constant: 8),
            
            // Keep toolbox above the swatch (equal spacing)
            toolbarView.bottomAnchor.constraint(lessThanOrEqualTo: colourSwatchView.topAnchor, constant: -8)
        ])
        
        // Swatch at bottom, full width
        NSLayoutConstraint.activate([
            colourSwatchView.leadingAnchor.constraint(equalTo: col.leadingAnchor),
            colourSwatchView.trailingAnchor.constraint(equalTo: col.trailingAnchor),
            colourSwatchView.bottomAnchor.constraint(equalTo: col.bottomAnchor),
            colourSwatchView.heightAnchor.constraint(equalToConstant: 54)
        ])
        
        // Give the toolbox a sane width inside the 101 column
        toolbarView.widthAnchor.constraint(lessThanOrEqualToConstant: 100).isActive = true
        
        // z-order to keep toolbox clickable
        view.addSubview(col, positioned: .above, relativeTo: nil)
    }
    
    // MARK: - UI builders
    
    private func setupStatusBar() {
        let status = NSTextField(labelWithString: "X: 0, Y: 0    Selection: —")
        status.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        status.alignment = .left
        status.lineBreakMode = .byTruncatingTail
        status.translatesAutoresizingMaskIntoConstraints = false
        status.wantsLayer = true
        status.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        status.layer?.cornerRadius = 4
        status.layer?.borderColor = NSColor.separatorColor.cgColor
        status.layer?.borderWidth = 1
        status.identifier = NSUserInterfaceItemIdentifier("StatusBar")
        view.addSubview(status)
        statusBarField = status
        
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 8),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            status.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    private func embedCanvasIfNeeded() {
        guard !didEmbedCanvasInScroll,
              let host = canvasView?.superview,
              let oldCanvas = canvasView else { return }
        
        didEmbedCanvasInScroll = true
        oldCanvas.removeFromSuperview()
        
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        scroll.identifier = NSUserInterfaceItemIdentifier("CanvasScrollView")
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 8.0
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        host.addSubview(scroll)
        canvasScrollView = scroll
        
        // Copyright just below the canvas area
        let sig = NSTextField(labelWithString: "© 2025 Paint95 — Jeffrey McIntosh")
        sig.translatesAutoresizingMaskIntoConstraints = false
        sig.alignment = .center
        sig.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        sig.textColor = .secondaryLabelColor
        sig.lineBreakMode = .byTruncatingTail
        host.addSubview(sig)
        signatureLabel = sig
        
        // Reserve a full band height: palette + strip + gaps
        let fullBand = -(kGapSigToPalette + kPaletteHeight + kGapPaletteToStrip + kStripHeight + kGapStripToStatus)
        
        NSLayoutConstraint.activate([
            // Canvas area to the right of the column, above the signature
            scroll.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: signatureLabel.topAnchor, constant: -4),
            
            // Signature spanning the content width, just above the “band”
            signatureLabel.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 8),
            signatureLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            signatureLabel.bottomAnchor.constraint(equalTo: statusBarField.topAnchor, constant: fullBand)
        ])
        
        // Document view must size itself
        oldCanvas.translatesAutoresizingMaskIntoConstraints = true
        scroll.documentView = oldCanvas
        oldCanvas.updateCanvasSize(to: oldCanvas.canvasRect.size)
    }
    
    private func placePaletteBetweenSignatureAndStatus() {
        colourPaletteView.removeFromSuperview()
        colourPaletteView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(colourPaletteView)
        
        NSLayoutConstraint.activate([
            colourPaletteView.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 8),
            colourPaletteView.topAnchor.constraint(equalTo: signatureLabel.bottomAnchor, constant: kGapSigToPalette),
            colourPaletteView.heightAnchor.constraint(equalToConstant: kPaletteHeight),
            // leave some room on the right for the size strip
            colourPaletteView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -180)
        ])
        
        colourPaletteView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        colourPaletteView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }
    
    private func placeToolSizeStripRightOfPalette() {
        let strip = ToolSizeSelectorView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.delegate = self
        view.addSubview(strip)
        toolSizeSelectorView = strip
        
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: colourPaletteView.trailingAnchor, constant: 8),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            strip.topAnchor.constraint(equalTo: colourPaletteView.bottomAnchor, constant: kGapPaletteToStrip),
            strip.heightAnchor.constraint(equalToConstant: kStripHeight),
            strip.bottomAnchor.constraint(equalTo: statusBarField.topAnchor, constant: -kGapStripToStatus)
        ])
        
        strip.setContentHuggingPriority(.defaultLow, for: .horizontal)
        strip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    // MARK: - Status updates from CanvasView
    func canvasStatusDidChange(cursor: NSPoint, selectionSize: NSSize?) {
        let x = Int(cursor.x.rounded())
        let y = Int(cursor.y.rounded())
        let selText: String = {
            if let s = selectionSize, s.width > 0, s.height > 0 {
                return "Selection: \(Int(s.width))×\(Int(s.height))"
            } else {
                return "Selection: —"
            }
        }()
        statusBarField?.stringValue = "X: \(x), Y: \(y)    \(selText)"
    }
    
    // MARK: - Colour picker window
    func presentColourSelection() {
        let initialRGB: [Double]
        if canvasView.colourFromSelectionWindow {
            initialRGB = AppColourState.shared.rgb
        } else {
            guard let rgb = canvasView.currentColour.usingColorSpace(.deviceRGB) else { return }
            initialRGB = [Double(rgb.redComponent * 255.0),
                          Double(rgb.greenComponent * 255.0),
                          Double(rgb.blueComponent * 255.0)]
        }
        
        let controller = ColourSelectionWindowController(
            initialRGB: initialRGB,
            onColourSelected: { [weak self] newColour in
                NotificationCenter.default.post(name: .colourPicked, object: newColour)
                self?.colourWindowController = nil
            },
            onCancel: { [weak self] in
                self?.colourWindowController = nil
            }
        )
        colourWindowController = controller
        controller.showWindow(self.view.window)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Keyboard routing
    func handleGlobalKeyDown(_ event: NSEvent) -> NSEvent? {
        if NSApp.keyWindow !== self.view.window { return event }
        if let fr = self.view.window?.firstResponder, !(fr is CanvasView) { return event }
        switch event.keyCode {
        case 51, 117: canvasView.deleteSelectionOrPastedImage(); return nil   // delete / fn-delete
        case 123: canvasView.moveSelectionBy(dx: -1, dy: 0); return nil
        case 124: canvasView.moveSelectionBy(dx:  1, dy: 0); return nil
        case 125: canvasView.moveSelectionBy(dx:  0, dy: -1); return nil
        case 126: canvasView.moveSelectionBy(dx:  0, dy: 1); return nil
        default: return event
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 {
            canvasView.deleteSelectionOrPastedImage()
        } else {
            super.keyDown(with: event)
        }
    }
    
    @objc func updateColourSwatch(_ notification: Notification) {
        if let colour = notification.object as? NSColor {
            colourSwatchView.colour = colour
        }
    }
    
    // MARK: - ToolbarDelegate
    func toolSelected(_ tool: PaintTool) { canvasView.currentTool = tool }
    func toolSizeSelected(_ size: CGFloat) { canvasView.toolSize = size }
    
    // MARK: - ColourPaletteDelegate
    func colourSelected(_ colour: NSColor) {
        canvasView.currentColour = colour
        canvasView.colourFromSelectionWindow = false
        guard let rgb = colour.usingColorSpace(.deviceRGB) else { return }
        AppColourState.shared.rgb = [
            Double(rgb.redComponent * 255.0),
            Double(rgb.greenComponent * 255.0),
            Double(rgb.blueComponent * 255.0)
        ]
        colourSwatchView.colour = rgb
    }
    
    // Optional: Clear button or menu action
    @IBAction func clearCanvas(_ sender: Any) {
        canvasView.clearCanvas()
    }
    
    // CanvasViewDelegate (colour pick)
    func didPickColour(_ colour: NSColor) {
        canvasView.currentColour = colour
        colourPaletteView.selectedColour = colour
        colourPaletteView.needsDisplay = true
        colourSwatchView.colour = colour
    }
    // MARK: - Visibility helpers (used by AppDelegate View menu)
    var isToolBoxVisible: Bool {
        return !toolbarView.isHidden
    }

    var isColorBoxVisible: Bool {
        return !colourPaletteView.isHidden
    }

    func setToolBoxVisible(_ visible: Bool) {
        toolbarView.isHidden = !visible
        // If hiding/showing affects layout, you can animate and relayout:
        view.layoutSubtreeIfNeeded()
    }

    func setColorBoxVisible(_ visible: Bool) {
        colourPaletteView.isHidden = !visible
        view.layoutSubtreeIfNeeded()
    }
}

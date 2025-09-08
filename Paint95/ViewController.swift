// ViewController.swift
import Cocoa
import AppKit

extension Notification.Name {
    /// Broadcast when a new palette is loaded; object is [NSColor]
    static let paletteLoaded = Notification.Name("Paint95PaletteLoaded")
}

final class FreezableClipView: NSClipView {
    var isFrozen = false
    var frozenOrigin: NSPoint = .zero

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: isFrozen ? frozenOrigin : newOrigin)
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        if isFrozen {
            // Keep the origin pinned while allowing size constraints.
            r.origin = frozenOrigin
        }
        return r
    }
}

extension ViewController {

    // MARK: Options ▸ Colours…
    @IBAction func optionsColours(_ sender: Any?) {
        // Reuse your existing programmatic colour window
        canvasView?.showColourSelectionWindow()
    }

    // MARK: Options ▸ Get Colours…
    @IBAction func optionsGetColours(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Get Colours"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["gpl", "pal", "clr"]  // GIMP, JASC/Windows PAL, Apple Color List

        let present: (NSOpenPanel) -> Void = { p in
            p.beginSheetModal(for: self.view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] resp in
                guard resp == .OK, let url = p.url else { return }
                self?.importPalette(from: url)
            }
        }

        if let w = view.window {
            panel.beginSheetModal(for: w) { [weak self] resp in
                guard resp == .OK, let url = panel.url else { return }
                self?.importPalette(from: url)
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                importPalette(from: url)
            }
        }
    }

    // MARK: - Palette import + fan-out
    private func importPalette(from url: URL) {
        do {
            let colors = try PaletteImporter.importPalette(url: url)
            if colors.isEmpty {
                presentErrorAlert(title: "No Colours Found",
                                  message: "The file didn’t contain any usable colours.")
                return
            }

            // Broadcast to whoever owns/draws the palette strip
            NotificationCenter.default.post(name: .paletteLoaded, object: colors)

            // (Optional) Keep a shared copy for later use if you have a global store.
            // SharedPalette.colours = colors

        } catch {
            presentErrorAlert(title: "Couldn’t Load Colours",
                              message: "\(error.localizedDescription)\n\nFile: \(url.lastPathComponent)")
        }
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let w = view.window {
            alert.beginSheetModal(for: w, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}

enum PaletteImporter {
    enum ImportError: LocalizedError {
        case unsupportedType
        case parseFailure(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedType:            return "Unsupported palette type."
            case .parseFailure(let why):      return "Couldn’t parse palette: \(why)"
            }
        }
    }

    static func importPalette(url: URL) throws -> [NSColor] {
        switch url.pathExtension.lowercased() {
        case "gpl": return try loadGimpGPL(url: url)
        case "pal": return try loadJASCPAL(url: url)       // JASC-PAL text
        case "clr": return try loadAppleCLR(url: url)
        default:    throw ImportError.unsupportedType
        }
    }

    // GIMP .gpl
    private static func loadGimpGPL(url: URL) throws -> [NSColor] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var colors: [NSColor] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let low = line.lowercased()
            if low.hasPrefix("gimp palette") || low.hasPrefix("name:") || low.hasPrefix("columns:") { continue }

            // "R G B [optional name]"
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3,
                  let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]) else { continue }

            colors.append(NSColor(srgbRed: CGFloat(r)/255.0,
                                  green:  CGFloat(g)/255.0,
                                  blue:   CGFloat(b)/255.0,
                                  alpha:  1.0))
        }
        return colors
    }

    // JASC-PAL (text)
    private static func loadJASCPAL(url: URL) throws -> [NSColor] {
        let text = try String(contentsOf: url, encoding: .ascii)
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 3 else { throw ImportError.parseFailure("Too few lines for JASC-PAL.") }
        guard lines[0].uppercased() == "JASC-PAL" else {
            throw ImportError.parseFailure("Missing JASC-PAL header.")
        }
        guard lines[1] == "0100" || lines[1] == "0101" else {
            throw ImportError.parseFailure("Unsupported JASC version \(lines[1]).")
        }
        guard let count = Int(lines[2]), count >= 0 else {
            throw ImportError.parseFailure("Invalid colour count.")
        }

        var colors: [NSColor] = []
        for i in 0..<min(count, max(0, lines.count - 3)) {
            let parts = lines[3 + i].split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3,
                  let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]) else { continue }

            colors.append(NSColor(srgbRed: CGFloat(r)/255.0,
                                  green:  CGFloat(g)/255.0,
                                  blue:   CGFloat(b)/255.0,
                                  alpha:  1.0))
        }
        return colors
    }

    // Apple Color List .clr
    private static func loadAppleCLR(url: URL) throws -> [NSColor] {
        guard let list = NSColorList(name: NSColorList.Name(url.deletingPathExtension().lastPathComponent),
                                     fromFile: url.path) else {
            throw ImportError.parseFailure("Couldn’t read .clr color list.")
        }
        var colors: [NSColor] = []
        for key in list.allKeys {
            // normalize to sRGB to avoid appearance / color-space drift
            if let c = list.color(withKey: key)?.usingColorSpace(.sRGB) {
                colors.append(c)
            }
        }
        return colors
    }
}

enum PaletteExporter {
    enum Error: LocalizedError {
        case unsupportedType
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedType:          return "Unsupported palette type."
            case .writeFailed(let why):     return "Write failed: \(why)"
            }
        }
    }

    // MARK: .gpl (GIMP Palette)
    // Writes 0–255 sRGB triplets. Uses Columns: 8 to match the UI’s 8×2 grid.
    static func saveGPL(_ colors: [NSColor], to url: URL, name: String = "Paint95 Palette") throws {
        var out = "GIMP Palette\n"
        out += "Name: \(name)\n"
        out += "Columns: 8\n"
        out += "# Exported by Paint95\n"
        for c in colors {
            let (r,g,b) = srgb255(c)
            out += String(format: "%3d %3d %3d\tColor\n", r, g, b)
        }
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw Error.writeFailed(error.localizedDescription)
        }
    }

    // MARK: JASC-PAL (text)
    // Format:
    //   JASC-PAL
    //   0100
    //   <count>
    //   R G B
    static func saveJASCPAL(_ colors: [NSColor], to url: URL) throws {
        var out = "JASC-PAL\n0100\n\(colors.count)\n"
        for c in colors {
            let (r,g,b) = srgb255(c)
            out += "\(r) \(g) \(b)\n"
        }
        do {
            try out.write(to: url, atomically: true, encoding: .ascii)
        } catch {
            throw Error.writeFailed(error.localizedDescription)
        }
    }

    // MARK: Apple .clr (NSColorList)
    // Stores NSColors in the list *as sRGB* to avoid color-space drift later.
    static func saveCLR(_ colors: [NSColor], to url: URL) throws {
        let base = url.deletingPathExtension().lastPathComponent
        let listName = base.isEmpty ? "Paint95 Palette" : base
        let name = NSColorList.Name(listName)
        let list = NSColorList(name: name)

        for (i, c) in colors.enumerated() {
            let key = "Color \(i + 1)"
            list.setColor(c.usingColorSpace(.sRGB) ?? c, forKey: key)
        }

        // Legacy-but-reliable API for writing .clr to disk
        if !list.write(toFile: url.path) {
            throw Error.writeFailed("NSColorList write failed.")
        }
    }

    // MARK: - Helpers

    /// Convert any NSColor to 0–255 sRGB components with clamping+rounding.
    private static func srgb255(_ c: NSColor) -> (Int, Int, Int) {
        let s = c.usingColorSpace(.sRGB) ?? c.usingColorSpace(.deviceRGB) ?? c
        let r = Int(round(s.redComponent   * 255.0)).clamped(0, 255)
        let g = Int(round(s.greenComponent * 255.0)).clamped(0, 255)
        let b = Int(round(s.blueComponent  * 255.0)).clamped(0, 255)
        return (r, g, b)
    }
}

private extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

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
            // Left edge just right of the fixed left column
            colourPaletteView.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 8),

            // Align the palette's bottom with the same baseline the tool-size bar uses
            colourPaletteView.bottomAnchor.constraint(equalTo: statusBarField.topAnchor, constant: -kGapStripToStatus),

            // Keep the palette a fixed height
            colourPaletteView.heightAnchor.constraint(equalToConstant: kPaletteHeight),

            // Leave some room on the right for the size strip
            colourPaletteView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -180),

            // Ensure it never overlaps the signature (acts as a ceiling)
            colourPaletteView.topAnchor.constraint(greaterThanOrEqualTo: signatureLabel.bottomAnchor, constant: kGapSigToPalette)
        ])

        colourPaletteView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        colourPaletteView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    private func placeToolSizeStripRightOfPalette() {
        let strip = ToolSizeSelectorView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.delegate = self
        strip.selectedSize = canvasView.toolSize
        view.addSubview(strip)
        toolSizeSelectorView = strip

        NSLayoutConstraint.activate([
            // Sits to the right of the palette
            strip.leadingAnchor.constraint(equalTo: colourPaletteView.trailingAnchor, constant: 8),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            // Align bottoms with the palette (shared baseline above status bar)
            strip.bottomAnchor.constraint(equalTo: statusBarField.topAnchor, constant: -kGapStripToStatus),

            // Fixed height for the strip
            strip.heightAnchor.constraint(equalToConstant: kStripHeight)
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

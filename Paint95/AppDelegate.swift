// AppDelegate.swift
import Cocoa

private extension NSView {
    var descendants: [NSView] {
        subviews.flatMap { [$0] + $0.descendants }
    }
}

private extension CanvasView {
    // Call from AppDelegate safely
    func setDrawOpaqueIfAvailable(_ flag: Bool) {
        // If your CanvasView already has `drawOpaque`, this will work after you add it.
        // Otherwise, no-op (keeps AppDelegate decoupled).
        if responds(to: Selector(("setDrawOpaque:"))) {
            setValue(flag, forKey: "drawOpaque")
        }
    }
}

// MARK: - Flip / Rotate sheet

final class FlipRotateSheetController: NSWindowController {
    private let flipNone = NSButton(radioButtonWithTitle: "None", target: nil, action: nil)
    private let flipH    = NSButton(radioButtonWithTitle: "Horizontal", target: nil, action: nil)
    private let flipV    = NSButton(radioButtonWithTitle: "Vertical",   target: nil, action: nil)

    private let rot0   = NSButton(radioButtonWithTitle: "0°",   target: nil, action: nil)
    private let rot90  = NSButton(radioButtonWithTitle: "90°",  target: nil, action: nil)
    private let rot180 = NSButton(radioButtonWithTitle: "180°", target: nil, action: nil)
    private let rot270 = NSButton(radioButtonWithTitle: "270°", target: nil, action: nil)

    private let onApply: (_ flipH: Bool, _ flipV: Bool, _ rotationDegrees: Int) -> Void

    init(onApply: @escaping (Bool, Bool, Int) -> Void) {
        self.onApply = onApply
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "Flip/Rotate"
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let panel = window else { return }

        // hook up radio actions for exclusivity
        [flipNone, flipH, flipV].forEach {
            $0.target = self
            $0.action = #selector(flipChanged(_:))
        }
        [rot0, rot90, rot180, rot270].forEach {
            $0.target = self
            $0.action = #selector(rotationChanged(_:))
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let flipLabel = NSTextField(labelWithString: "Flip:")
        flipLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        flipNone.state = .on
        let flipRow = NSStackView(views: [flipNone, flipH, flipV])
        flipRow.orientation = .horizontal
        flipRow.spacing = 12

        let rotLabel = NSTextField(labelWithString: "Rotate:")
        rotLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        rot0.state = .on
        let rotRow = NSStackView(views: [rot0, rot90, rot180, rot270])
        rotRow.orientation = .horizontal
        rotRow.spacing = 12

        let ok = NSButton(title: "OK", target: self, action: #selector(tapOK))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(tapCancel))
        cancel.keyEquivalent = "\u{1b}"
        let spring = NSView()
        let btnRow = NSStackView(views: [spring, cancel, ok])
        btnRow.orientation = .horizontal
        btnRow.alignment = .centerY
        btnRow.spacing = 8

        [flipLabel, flipRow, rotLabel, rotRow, btnRow].forEach { root.addArrangedSubview($0) }

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        panel.contentView = content

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    // enforce single selection within the Flip group
    @objc private func flipChanged(_ sender: NSButton) {
        for btn in [flipNone, flipH, flipV] {
            btn.state = (btn === sender) ? .on : .off
        }
    }

    // enforce single selection within the Rotate group
    @objc private func rotationChanged(_ sender: NSButton) {
        for btn in [rot0, rot90, rot180, rot270] {
            btn.state = (btn === sender) ? .on : .off
        }
    }

    @objc private func tapOK() {
        guard let panel = window, let parent = panel.sheetParent else { return }
        let flipHOn = flipH.state == .on
        let flipVOn = flipV.state == .on
        let rotation: Int = rot90.state == .on ? 90 : rot180.state == .on ? 180 : rot270.state == .on ? 270 : 0
        parent.endSheet(panel, returnCode: .OK)
        panel.close()
        onApply(flipHOn, flipVOn, rotation)
    }

    @objc private func tapCancel() {
        guard let panel = window, let parent = panel.sheetParent else { return }
        parent.endSheet(panel, returnCode: .cancel)
        panel.close()
    }
}

// MARK: - Stretch / Skew sheet

final class StretchSkewSheetController: NSWindowController, NSTextFieldDelegate {

    private let scaleXField = NSTextField(string: "100")
    private let scaleYField = NSTextField(string: "100")
    private let skewXField  = NSTextField(string: "0")
    private let skewYField  = NSTextField(string: "0")
    private let keepAspect  = NSButton(checkboxWithTitle: "Maintain aspect ratio", target: nil, action: nil)

    private let onApply: (_ scaleX: Int, _ scaleY: Int, _ skewX: Int, _ skewY: Int) -> Void

    init(onApply: @escaping (Int, Int, Int, Int) -> Void) {
        self.onApply = onApply
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "Stretch/Skew"
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let panel = window else { return }

        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return l
        }
        func configureField(_ tf: NSTextField, placeholder: String) {
            tf.placeholderString = placeholder
            tf.alignment = .right
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            tf.delegate = self
        }

        [scaleXField, scaleYField, skewXField, skewYField].forEach { configureField($0, placeholder: "") }

        let grid = NSGridView(views: [
            [label("Scale X (%):"), scaleXField],
            [label("Scale Y (%):"), scaleYField],
            [label("Skew X (°):"),  skewXField],
            [label("Skew Y (°):"),  skewYField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        // Buttons row
        let ok = NSButton(title: "OK", target: self, action: #selector(tapOK))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(tapCancel))
        let spring = NSView()
        let btnRow = NSStackView(views: [spring, keepAspect, cancel, ok])
        btnRow.orientation = .horizontal
        btnRow.alignment = .centerY
        btnRow.spacing = 8

        // Root stack
        let root = NSStackView(views: [grid, btnRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        panel.contentView = content

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    // Mirror X% to Y% when "Maintain aspect" is on
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject? === scaleXField, keepAspect.state == .on else { return }
        scaleYField.stringValue = scaleXField.stringValue
    }

    @objc private func tapOK() {
        guard let panel = window, let parent = panel.sheetParent else { return }
        let sx = clamp(Int(scaleXField.stringValue) ?? 100, min: 1, max: 800)
        let sy = clamp(Int(scaleYField.stringValue) ?? 100, min: 1, max: 800)
        let kx = clamp(Int(skewXField.stringValue) ?? 0,   min: -89, max: 89)
        let ky = clamp(Int(skewYField.stringValue) ?? 0,   min: -89, max: 89)
        parent.endSheet(panel, returnCode: .OK)
        panel.orderOut(nil)
        onApply(sx, sy, kx, ky)
    }

    @objc private func tapCancel() {
        guard let panel = window, let parent = panel.sheetParent else { return }
        parent.endSheet(panel, returnCode: .cancel)
        panel.orderOut(nil)
    }

    private func clamp(_ v: Int, min: Int, max: Int) -> Int { Swift.max(min, Swift.min(max, v)) }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow?
    private var currentDocumentURL: URL?
    private var isDrawOpaque: Bool = true
    private var flipRotateWC: FlipRotateSheetController?
    private var stretchSkewWC: StretchSkewSheetController?

    // MARK: - App lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        constructMenuBar()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Disable automatic window tabbing so View > Tab Bar items won't appear
        if #available(macOS 10.12, *) {
            NSWindow.allowsAutomaticWindowTabbing = false
        }
        constructMenuBar()

        // Create the main window
        let frame = NSRect(x: 200, y: 200, width: 1000, height: 700)
        let win = NSWindow(contentRect: frame,
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered,
                           defer: false)
        win.title = "Paint95"
        self.window = win

        // sensible starting content size + free resizing
        window?.setContentSize(NSSize(width: 1100, height: 750))
        window?.styleMask.insert(.resizable)
        window?.contentMinSize = NSSize(width: 700, height: 500)
        window?.contentMaxSize = NSSize(width: 12000, height: 9000)
        window?.resizeIncrements = NSSize(width: 1, height: 1)
        window?.isRestorable = true
        window?.setFrameAutosaveName("Paint95MainWindow")

        // Load the storyboard VC
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let vc = (storyboard.instantiateInitialController() as? ViewController)
            ?? (storyboard.instantiateController(withIdentifier: "ViewController") as? ViewController) else {
            fatalError("Couldn’t load ViewController from Main.storyboard")
        }

        win.contentViewController = vc
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        canvasView()?.drawOpaque = isDrawOpaque
    }

    // MARK: - Menu bar

    private func constructMenuBar() {
        let main = NSMenu()

        // ===== App (Paint95) =====
        let appName = ProcessInfo.processInfo.processName
        let appItem = NSMenuItem()
        main.addItem(appItem)

        let appMenu = NSMenu(title: appName)

        let about = NSMenuItem(
            title: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(NSMenuItem.separator())

        let hide = NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)

        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(hideOthers)

        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAll.target = NSApp
        appMenu.addItem(showAll)

        appMenu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)

        appItem.submenu = appMenu

        // ===== File =====
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")

        func addFile(_ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            fileMenu.addItem(item)
        }

        addFile("New",            #selector(fileNew(_:)),       "n", [.command])
        addFile("Open…",          #selector(fileOpen(_:)),      "o", [.command])
        fileMenu.addItem(NSMenuItem.separator())
        addFile("Save",           #selector(fileSave(_:)),      "s", [.command])
        addFile("Save As…",       #selector(fileSaveAs(_:)),    "s", [.command, .shift])
        fileMenu.addItem(NSMenuItem.separator())
        addFile("Send…",          #selector(fileSend(_:)))
        addFile("Set As Wallpaper (Tiled)",    #selector(fileSetWallpaperTiled(_:)))
        addFile("Set As Wallpaper (Centered)", #selector(fileSetWallpaperCentered(_:)))
        fileMenu.addItem(NSMenuItem.separator())
        addFile("Exit",           #selector(fileExit(_:)))

        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // ===== Edit =====
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        func addEdit(_ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            editMenu.addItem(item)
        }

        addEdit("Undo",             #selector(editUndo(_:)),             "z", [.command])
        addEdit("Repeat",           #selector(editRepeat(_:)),           "y", [.command]) // Redo
        editMenu.addItem(NSMenuItem.separator())
        addEdit("Cut",              #selector(editCut(_:)),              "x", [.command])
        addEdit("Copy",             #selector(editCopy(_:)),             "c", [.command])
        addEdit("Paste",            #selector(editPaste(_:)),            "v", [.command])
        addEdit("Clear Selection",  #selector(editClearSelection(_:)),   "\u{8}", []) // Delete
        editMenu.addItem(NSMenuItem.separator())
        addEdit("Select All",       #selector(editSelectAll(_:)),        "a", [.command])
        editMenu.addItem(NSMenuItem.separator())
        addEdit("Set Canvas Size…", #selector(editSetCanvasSize(_:)))
        editMenu.addItem(NSMenuItem.separator())
        addEdit("Copy To…",         #selector(editCopyTo(_:)))
        addEdit("Paste From…",      #selector(editPasteFrom(_:)))

        // Strip automatic Dictation / Emoji / Substitutions etc.
        stripAutomaticEditExtras(from: editMenu)

        editItem.submenu = editMenu
        main.addItem(editItem)

        // ===== View =====
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")

        func addView(_ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            viewMenu.addItem(item)
            return item
        }

        let mToolBox   = addView("Tool Box",   #selector(viewToggleToolBox(_:)))
        let mColourBox = addView("Colour Box", #selector(viewToggleColorBox(_:)))
        let mStatusBar = addView("Status Bar", #selector(viewToggleStatusBar(_:)))
        viewMenu.addItem(NSMenuItem.separator())
        addView("Zoom (activate tool)", #selector(viewActivateZoomTool(_:)))
        viewMenu.addItem(NSMenuItem.separator())
        addView("Normal Size", #selector(viewNormalSize(_:)))
        addView("Large Size",  #selector(viewLargeSize(_:)))
        addView("Custom…",     #selector(viewCustomZoom(_:)))
        viewMenu.addItem(NSMenuItem.separator())
        addView("View Bitmap…", #selector(viewBitmap(_:)))

        // Initialize checkmarks from current UI state
        if let vc = vc() {
            mToolBox.state   = vc.isToolBoxVisible ? .on : .off
            mColourBox.state = vc.isColorBoxVisible ? .on : .off
            let statusHidden = (self.viewWithID("StatusBar")?.isHidden ?? false)
            mStatusBar.state = statusHidden ? .off : .on
        } else {
            mToolBox.state = .on
            mColourBox.state = .on
            mStatusBar.state = .on
        }

        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        // ===== Image =====
        let imageItem = NSMenuItem(title: "Image", action: nil, keyEquivalent: "")
        let imageMenu = NSMenu(title: "Image")

        func addImage(_ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            imageMenu.addItem(item)
            return item
        }

        addImage("Flip/Rotate…",  #selector(imageFlipRotate(_:)))
        addImage("Stretch/Skew…", #selector(imageStretchSkew(_:)))
        imageMenu.addItem(NSMenuItem.separator())
        addImage("Invert Colors", #selector(imageInvertColors(_:)))
        addImage("Attributes…",   #selector(imageAttributes(_:)))
        imageMenu.addItem(NSMenuItem.separator())
        addImage("Clear Image",   #selector(imageClear(_:)))

        // Draw Opaque (toggle)
        let opaqueItem = addImage("Draw Opaque", #selector(imageToggleDrawOpaque(_:)))
        opaqueItem.state = isDrawOpaque ? .on : .off

        imageItem.submenu = imageMenu
        main.addItem(imageItem)

        // ===== Placeholders =====
        main.addItem(makeEmptyMenu(title: "Options"))
        main.addItem(makeEmptyMenu(title: "Help"))

        NSApp.mainMenu = main
    }

    private func vc() -> ViewController? {
        if let v = NSApp.keyWindow?.contentViewController as? ViewController { return v }
        return NSApp.windows.compactMap { $0.contentViewController as? ViewController }.first
    }

    private func canvasScrollView() -> NSScrollView? {
        // CanvasView -> NSClipView -> NSScrollView
        guard let clip = vc()?.canvasView.superview as? NSClipView else { return nil }
        return clip.superview as? NSScrollView
    }

    private func viewWithID(_ id: String) -> NSView? {
        guard let root = vc()?.view else { return nil }
        return root.descendants.first { $0.identifier?.rawValue == id }
    }

    private func setHidden(_ hidden: Bool, id: String) {
        viewWithID(id)?.isHidden = hidden
    }

    // MARK: View menu actions

    @objc private func viewToggleToolBox(_ sender: NSMenuItem) {
        guard let vc = vc() else { return }
        let newVisible = !vc.isToolBoxVisible
        vc.setToolBoxVisible(newVisible)
        sender.state = newVisible ? .on : .off
    }

    @objc private func viewToggleColorBox(_ sender: NSMenuItem) {
        guard let vc = vc() else { return }
        let newVisible = !vc.isColorBoxVisible
        vc.setColorBoxVisible(newVisible)
        sender.state = newVisible ? .on : .off
    }

    @objc private func viewToggleStatusBar(_ sender: NSMenuItem) {
        let willHide = sender.state == .on
        setHidden(willHide, id: "StatusBar")
        sender.state = willHide ? .off : .on
    }

    @objc private func viewActivateZoomTool(_ sender: Any?) {
        guard let c = vc()?.canvasView else { return }
        c.currentTool = .zoom
        NotificationCenter.default.post(name: .toolChanged, object: PaintTool.zoom)
    }

    @objc private func viewNormalSize(_ sender: Any?) {
        guard let scroll = canvasScrollView() else { return }
        scroll.magnification = 1.0
    }

    @objc private func viewLargeSize(_ sender: Any?) {
        guard let scroll = canvasScrollView() else { return }
        scroll.magnification = 2.0
    }

    @objc private func viewCustomZoom(_ sender: Any?) {
        guard let scroll = canvasScrollView() else { return }
        let alert = NSAlert()
        alert.messageText = "Custom Zoom"
        alert.informativeText = "Enter zoom percentage (e.g., 150 for 150%)."
        let field = NSTextField(string: "\(Int(scroll.magnification * 100))")
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let pct = max(10, min(800, Int(field.stringValue) ?? 100))
        scroll.magnification = CGFloat(pct) / 100.0
    }

    @objc private func viewBitmap(_ sender: Any?) {
        guard let image = snapshotCanvas() else { return }

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.frame = NSRect(origin: .zero, size: image.size)

        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.borderType = .bezelBorder
        sv.documentView = imageView
        sv.allowsMagnification = true
        sv.minMagnification = 0.25
        sv.maxMagnification = 8.0

        let w = NSWindow(
            contentRect: NSRect(x: 340, y: 340, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Bitmap (1:1)"
        w.contentView = sv
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Image menu actions

    @objc func imageFlipRotate(_ sender: Any?) {
        guard let win = NSApp.keyWindow,
              let canvas = findCanvasView()
        else { return }

        let c = FlipRotateSheetController { [weak canvas] flipH, flipV, deg in
            canvas?.applyFlipRotate(flipHorizontal: flipH, flipVertical: flipV, rotationDegrees: deg)
        }
        self.flipRotateWC = c
        guard let sheet = c.window else { return }
        win.beginSheet(sheet) { [weak self] _ in
            self?.flipRotateWC = nil
        }
    }

    @objc func imageStretchSkew(_ sender: Any?) {
        guard let win = NSApp.keyWindow,
              let canvas = findCanvasView()
        else { return }

        let c = StretchSkewSheetController { [weak canvas] sx, sy, kx, ky in
            canvas?.applyStretchSkew(scaleXPercent: sx, scaleYPercent: sy, skewXDegrees: kx, skewYDegrees: ky)
        }
        self.stretchSkewWC = c
        guard let sheet = c.window else { return }
        win.beginSheet(sheet) { [weak self] _ in
            self?.stretchSkewWC = nil
        }
    }

    @objc private func imageInvertColors(_ sender: Any?) {
        guard let canvas = canvasView(), let src = canvas.canvasImage else { return }
        guard let inv = src.invertedRGB() else { NSSound.beep(); return }
        canvas.canvasImage = inv
        canvas.needsDisplay = true
    }

    @objc private func imageAttributes(_ sender: Any?) {
        // Reuse your existing size dialog (Edit > Set Canvas Size…)
        editSetCanvasSize(sender)
    }

    @objc private func imageClear(_ sender: Any?) {
        guard let canvas = canvasView() else { return }
        let s = canvas.canvasRect.size
        let img = NSImage(size: s)
        img.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: s)).fill()
        img.unlockFocus()

        canvas.canvasImage = img
        canvas.needsDisplay = true
    }

    @objc private func imageToggleDrawOpaque(_ sender: NSMenuItem) {
        isDrawOpaque.toggle()
        sender.state = isDrawOpaque ? .on : .off
        // Propagate to CanvasView if you expose a property
        canvasView()?.setDrawOpaqueIfAvailable(isDrawOpaque)
    }

    // MARK: - Edit actions

    @objc func editUndo(_ sender: Any?) {
        findCanvasView()?.undo()
    }

    @objc func editRepeat(_ sender: Any?) { // Redo
        findCanvasView()?.redo()
    }

    @objc func editCut(_ sender: Any?) {
        findCanvasView()?.cutSelection()
    }

    @objc func editCopy(_ sender: Any?) {
        findCanvasView()?.copySelection()
    }

    /// Copy To… — Save the current selection to a file (does not modify the canvas)
    @objc func editCopyTo(_ sender: Any?) {
        guard let canvas = findCanvasView() else { return }

        // Build an image from the current selection (prefer existing selectedImage)
        guard let selectionImage = currentSelectionImage(from: canvas) else {
            NSSound.beep()
            print("Copy To…: no selection.")
            return
        }

        // Choose a folder, then prompt for file name
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        let suggested = "Selection.png"
        let alert = NSAlert()
        alert.messageText = "Copy To…"
        alert.informativeText = "Enter a file name for the selection:"
        let nameField = NSTextField(string: suggested)
        nameField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = nameField
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var filename = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty { filename = suggested }
        if (filename as NSString).pathExtension.isEmpty { filename += ".png" }
        let url = dir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: url.path) {
            let ow = NSAlert()
            ow.messageText = "Replace existing file?"
            ow.informativeText = "A file named “\(filename)” already exists in this location."
            ow.alertStyle = .warning
            ow.addButton(withTitle: "Replace")
            ow.addButton(withTitle: "Cancel")
            guard ow.runModal() == .alertFirstButtonReturn else { return }
        }

        // Encode (default PNG)
        guard
            let tiff = selectionImage.tiffRepresentation,
            let rep  = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else {
            NSSound.beep()
            print("Copy To…: failed to encode selection.")
            return
        }
        do {
            try data.write(to: url)
            print("Copy To…: saved selection to \(url.path)")
        } catch {
            NSSound.beep()
            print("Copy To…: save error \(error)")
        }
    }

    /// Paste From… — Choose an image file and paste it as a floating selection
    @objc func editPasteFrom(_ sender: Any?) {
        guard let canvas = findCanvasView() else { return }

        let panel = NSOpenPanel()
        panel.title = "Paste From…"
        panel.allowedFileTypes = ["png","jpg","jpeg","bmp","tiff","gif","heic"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }

            // Put the image on the pasteboard, then reuse CanvasView.pasteImage()
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])

            canvas.pasteImage()
        }
    }

    @objc func editPaste(_ sender: Any?) {
        findCanvasView()?.pasteImage()
    }

    @objc func editClearSelection(_ sender: Any?) {
        findCanvasView()?.deleteSelectionOrPastedImage()
    }

    @objc func editSelectAll(_ sender: Any?) {
        if let canvas = findCanvasView() {
            // Reuse same behavior as ⌘A in your CanvasView
            canvas.performKeyEquivalent(with: makeCommandEvent(char: "a"))
        }
    }

    @objc func editSetCanvasSize(_ sender: Any?) {
        guard let canvas = findCanvasView() else { return }
        let currentSize = canvas.canvasRect.size

        // Build a small form using an alert accessory view
        let alert = NSAlert()
        alert.messageText = "Canvas Size:"
        alert.informativeText = "Enter the new size in pixels."
        alert.alertStyle = .informational

        // Accessory view with two labeled fields (Width / Height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))

        let widthLabel  = NSTextField(labelWithString: "Width:")
        widthLabel.frame = NSRect(x: 0, y: 30, width: 60, height: 22)

        let heightLabel = NSTextField(labelWithString: "Height:")
        heightLabel.frame = NSRect(x: 0, y: 4, width: 60, height: 22)

        let widthField = NSTextField(string: String(Int(currentSize.width)))
        widthField.alignment = .right
        widthField.frame = NSRect(x: 70, y: 28, width: 200, height: 24)

        let heightField = NSTextField(string: String(Int(currentSize.height)))
        heightField.alignment = .right
        heightField.frame = NSRect(x: 70, y: 2, width: 200, height: 24)

        container.addSubview(widthLabel)
        container.addSubview(heightLabel)
        container.addSubview(widthField)
        container.addSubview(heightField)

        alert.accessoryView = container
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Parse & clamp
        let w = max(CGFloat(Int(widthField.stringValue) ?? Int(currentSize.width)), 1)
        let h = max(CGFloat(Int(heightField.stringValue) ?? Int(currentSize.height)), 1)

        // Resize anchored at TOP-LEFT
        canvas.setCanvasSizeAnchoredTopLeft(to: NSSize(width: w, height: h))
    }

    /// Remove “Start Dictation…”, “Emoji & Symbols”, and various automatic text-service groups
    private func stripAutomaticEditExtras(from menu: NSMenu) {
        let forbiddenSelectors: Set<Selector> = [
            #selector(NSApplication.orderFrontCharacterPalette(_:))
        ]
        let forbiddenTitles = Set([
            "Start Dictation…",
            "Emoji & Symbols",
            "Emoji & Symbols…",
            "Substitutions",
            "Transformations",
            "Speech",
            "Text Replacement",
            "AutoFill"
        ])

        for item in menu.items.reversed() {
            if let action = item.action, forbiddenSelectors.contains(action) {
                menu.removeItem(item)
                continue
            }
            if forbiddenTitles.contains(item.title) {
                menu.removeItem(item)
                continue
            }
            if let submenu = item.submenu, forbiddenTitles.contains(submenu.title) {
                menu.removeItem(item)
            }
        }
    }

    private func makeEmptyMenu(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        let empty = NSMenuItem(title: "<empty>", action: nil, keyEquivalent: "")
        empty.isEnabled = false
        menu.addItem(empty)
        item.submenu = menu
        return item
    }

    // MARK: - File actions

    @MainActor
    private func findCanvasView() -> CanvasView? {
        if let vc = NSApp.keyWindow?.contentViewController as? ViewController {
            return vc.canvasView
        }
        for w in NSApp.windows {
            if let vc = w.contentViewController as? ViewController {
                return vc.canvasView
            }
        }
        return nil
    }

    @MainActor
    @IBAction func fileSave(_ sender: Any?) {
        if let url = currentDocumentURL {
            doSave(to: url)
            return
        }
        fileSaveAs(sender)
    }

    @MainActor
    @IBAction func fileSaveAs(_ sender: Any?) {
        // Folder chooser (avoids NSSavePanel crash you hit earlier)
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        let suggested: String = {
            if let current = currentDocumentURL?.deletingPathExtension().lastPathComponent, !current.isEmpty {
                return current + ".png"
            } else {
                return "Untitled.png"
            }
        }()

        let alert = NSAlert()
        alert.messageText = "Save As"
        alert.informativeText = "Enter a file name:"
        let nameField = NSTextField(string: suggested)
        nameField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = nameField
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var filename = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty { filename = suggested }
        if (filename as NSString).pathExtension.isEmpty { filename += ".png" }
        let url = dir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: url.path) {
            let ow = NSAlert()
            ow.messageText = "Replace existing file?"
            ow.informativeText = "A file named “\(filename)” already exists in this location."
            ow.alertStyle = .warning
            ow.addButton(withTitle: "Replace")
            ow.addButton(withTitle: "Cancel")
            guard ow.runModal() == .alertFirstButtonReturn else { return }
        }

        currentDocumentURL = url
        doSave(to: url)
    }

    @objc func fileNew(_ sender: Any?) {
        currentDocumentURL = nil
        canvasView()?.clearCanvas()
    }

    @objc func fileOpen(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedFileTypes = ["png","jpg","jpeg","bmp","tiff","gif","heic"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            guard let canvas = self?.canvasView() else { return }

            canvas.canvasImage = image.copy() as? NSImage
            canvas.canvasRect = NSRect(origin: .zero, size: image.size)
            canvas.updateCanvasSize(to: image.size)
            canvas.needsDisplay = true

            self?.currentDocumentURL = url
        }
    }

    // MARK: - Send (email)

    @MainActor
    @objc func fileSend(_ sender: Any?) {
        guard let attachmentURL = exportSnapshotToTemporaryPNG() else {
            NSSound.beep()
            print("Send: could not create attachment.")
            return
        }
        guard let service = NSSharingService(named: .composeEmail) else {
            NSSound.beep()
            print("Send: Mail compose service unavailable.")
            return
        }
        service.recipients = []
        service.subject = "Image from Paint95"
        let body = "Hi,\n\nSharing an image from Paint95.\n\n– Sent from Paint95"
        let items: [Any] = [body as NSString, attachmentURL as NSURL]
        if service.canPerform(withItems: items) {
            service.perform(withItems: items)
        } else {
            NSSound.beep()
            print("Send: Cannot perform share with provided items.")
        }
    }

    private func exportSnapshotToTemporaryPNG() -> URL? {
        guard let image = snapshotCanvas() ?? canvasView()?.canvasImage else { return nil }
        guard
            let tiff = image.tiffRepresentation,
            let rep  = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Paint95-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("Send: failed to write temp file: \(error)")
            return nil
        }
    }

    // MARK: - Wallpaper

    @objc func fileSetWallpaperTiled(_ sender: Any?) {
        guard confirmWallpaperChange() else { return }
        setDesktopWallpaper(mode: .tiled)
    }

    @objc func fileSetWallpaperCentered(_ sender: Any?) {
        guard confirmWallpaperChange() else { return }
        setDesktopWallpaper(mode: .centered)
    }

    @objc func fileExit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private enum WallpaperMode { case tiled, centered }

    private func confirmWallpaperChange() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Set as Desktop Wallpaper?"
        alert.informativeText = "This action will update your Desktop Wallpaper. Are you sure?"
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func setDesktopWallpaper(mode: WallpaperMode) {
        guard let source = snapshotCanvas() else { return }
        for (idx, screen) in NSScreen.screens.enumerated() {
            let screenSize = screen.frame.size
            let rendered: NSImage = {
                switch mode {
                case .tiled:   return imageForScreenTiled(source: source, screenSize: screenSize)
                case .centered:return imageForScreenCentered(source: source, screenSize: screenSize)
                }
            }()

            guard
                let tiff = rendered.tiffRepresentation,
                let rep  = NSBitmapImageRep(data: tiff),
                let data = rep.representation(using: .png, properties: [:])
            else { continue }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("paint95-wallpaper-\(idx).png")
            do { try data.write(to: tempURL) } catch { continue }

            let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .imageScaling: NSNumber(value: NSImageScaling.scaleNone.rawValue),
                .allowClipping: true
            ]

            try? NSWorkspace.shared.setDesktopImageURL(tempURL, for: screen, options: options)
        }
    }

    private func imageForScreenTiled(source: NSImage, screenSize: NSSize) -> NSImage {
        let out = NSImage(size: screenSize)
        out.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: screenSize)).fill()

        let tile = source.size
        guard tile.width > 0, tile.height > 0 else { out.unlockFocus(); return out }

        var y: CGFloat = 0
        while y < screenSize.height {
            var x: CGFloat = 0
            while x < screenSize.width {
                source.draw(in: NSRect(x: x, y: y, width: tile.width, height: tile.height),
                            from: .zero, operation: .sourceOver, fraction: 1.0)
                x += tile.width
            }
            y += tile.height
        }
        out.unlockFocus()
        return out
    }

    private func imageForScreenCentered(source: NSImage, screenSize: NSSize) -> NSImage {
        let out = NSImage(size: screenSize)
        out.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: screenSize)).fill()

        let s = source.size
        let origin = NSPoint(x: (screenSize.width - s.width)/2.0, y: (screenSize.height - s.height)/2.0)
        source.draw(in: NSRect(origin: origin, size: s),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    // MARK: - Save helper

    private func doSave(to url: URL) {
        guard let image = snapshotCanvas() ?? canvasView()?.canvasImage else { return }

        let ext = url.pathExtension.lowercased()
        let fileType: NSBitmapImageRep.FileType
        switch ext {
        case "png":  fileType = .png
        case "jpg", "jpeg": fileType = .jpeg
        case "bmp":  fileType = .bmp
        case "tiff": fileType = .tiff
        default:     fileType = .png
        }

        guard
            let tiff = image.tiffRepresentation,
            let rep  = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: fileType, properties: [:])
        else {
            NSSound.beep()
            print("Failed to encode image for saving.")
            return
        }

        do {
            try data.write(to: url)
            print("Saved to \(url.path)")
        } catch {
            NSSound.beep()
            print("Save error: \(error)")
        }
    }

    // MARK: - Canvas / VC helpers

    private func mainViewController() -> ViewController? {
        if let vc = NSApp.keyWindow?.contentViewController as? ViewController { return vc }
        return NSApp.windows.compactMap { $0.contentViewController as? ViewController }.first
    }

    private func canvasView() -> CanvasView? {
        mainViewController()?.canvasView
    }

    private func snapshotCanvas() -> NSImage? {
        guard let canvas = canvasView() else { return nil }
        let size = canvas.intrinsicContentSize == .zero ? canvas.bounds.size : canvas.intrinsicContentSize
        let bounds = NSRect(origin: .zero, size: size)
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        canvas.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func makeCommandEvent(char: String) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: 0
        )!
    }

    /// Extract the current selection as an image (selectedImage if present, else render selectionRect)
    private func currentSelectionImage(from canvas: CanvasView) -> NSImage? {
        if let img = canvas.selectedImage {
            return img
        }
        if let rect = canvas.selectionRect, let base = canvas.canvasImage {
            let image = NSImage(size: rect.size)
            image.lockFocus()
            base.draw(at: .zero, from: rect, operation: .copy, fraction: 1.0)
            image.unlockFocus()
            return image
        }
        return nil
    }
}

extension NSImage {
    func invertedRGB() -> NSImage? {
        guard let rep = rgba8Bitmap(), let data = rep.bitmapData else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let spp = rep.samplesPerPixel   // 4
        let bpr = rep.bytesPerRow

        for y in 0..<h {
            let row = data.advanced(by: y * bpr)
            for x in 0..<w {
                let p = row.advanced(by: x * spp)
                p[0] = 255 &- p[0]   // R
                p[1] = 255 &- p[1]   // G
                p[2] = 255 &- p[2]   // B
                // p[3] alpha unchanged
            }
        }
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}

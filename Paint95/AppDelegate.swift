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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private weak var activeSaveAsPanel: NSSavePanel?
    private var lastSavedSnapshot: Data?
    var window: NSWindow?
    private var currentDocumentURL: URL?
    private var isDrawOpaque: Bool = true
    private var flipRotateWC: FlipRotateSheetController?
    private var stretchSkewWC: StretchSkewSheetController?

    // Retain the Help Topics window so it doesn't deallocate while open
    private var helpTopicsWC: NSWindowController?

    // --- Save As: format popup state ---
    private var saveAsFormatPopup: NSPopUpButton?
    private var lastSaveFormat: SaveFormat = .png

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

        // Establish "clean" baseline for the initial blank canvas
        DispatchQueue.main.async { [weak self] in
            self?.refreshBaselineSnapshot()
        }

        // Observe canvas modifications to show the "edited" dot in titlebar
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCanvasModified(_:)),
                                               name: .canvasDidModify,
                                               object: nil)
    }

    @objc private func handleCanvasModified(_ note: Notification) {
        window?.isDocumentEdited = true
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
            action: #selector(showAboutPaint(_:)),
            keyEquivalent: ""
        )
        about.target = self
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

        let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(fileExit(_:)), keyEquivalent: "q")
        quit.target = self
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

        // ===== Options =====
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu(title: "Options")

        let colours = NSMenuItem(title: "Colours…",
                                 action: #selector(ViewController.optionsColours(_:)),
                                 keyEquivalent: ",")
        colours.keyEquivalentModifierMask = [.command]
        colours.target = nil // use responder chain (ViewController implements the action)
        optionsMenu.addItem(colours)

        let getColours = NSMenuItem(title: "Get Colours…",
                                    action: #selector(ViewController.optionsGetColours(_:)),
                                    keyEquivalent: "")
        getColours.target = nil
        optionsMenu.addItem(getColours)

        optionsMenu.addItem(NSMenuItem.separator())

        // NEW: Save / Restore
        let saveColours = NSMenuItem(title: "Save Colours…",
                                     action: #selector(optionsSaveColours(_:)),
                                     keyEquivalent: "")
        saveColours.target = self
        optionsMenu.addItem(saveColours)

        let restoreDefaults = NSMenuItem(title: "Restore Default Colours",
                                         action: #selector(optionsRestoreDefaultColours(_:)),
                                         keyEquivalent: "")
        restoreDefaults.target = self
        optionsMenu.addItem(restoreDefaults)

        optionsItem.submenu = optionsMenu
        main.addItem(optionsItem)

        // ===== Help =====
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: "Help")

        let helpTopics = NSMenuItem(title: "Help Topics", action: #selector(showHelpTopics(_:)), keyEquivalent: "?")
        helpTopics.keyEquivalentModifierMask = [.command, .shift]
        helpTopics.target = self
        helpMenu.addItem(helpTopics)

        let aboutPaint = NSMenuItem(title: "About Paint", action: #selector(showAboutPaint(_:)), keyEquivalent: "")
        aboutPaint.target = self
        helpMenu.addItem(aboutPaint)

        helpItem.submenu = helpMenu
        main.addItem(helpItem)

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

    // --- NEW: Save As with format drop-down (BMP, GIF, JPEG, PNG, TIFF) ---
    @MainActor
    @IBAction func fileSaveAs(_ sender: Any?) {
        let panel = NSSavePanel()
        activeSaveAsPanel = panel                     // <-- keep reference
        defer { activeSaveAsPanel = nil }             // <-- clear on exit

        panel.title = "Save As"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let base = currentDocumentURL?.deletingPathExtension().lastPathComponent
        let suggestedBase = (base?.isEmpty == false ? base! : "Untitled")

        let currentExt = currentDocumentURL?.pathExtension.lowercased()
        let defaultExt = (currentExt?.isEmpty == false ? currentExt! : "png")
        panel.nameFieldStringValue = suggestedBase + "." + defaultExt

        let formats: [(title: String, ext: String)] = [
            ("PNG (.png)",   "png"),
            ("JPEG (.jpg)",  "jpg"),
            ("Bitmap (.bmp)","bmp"),
            ("TIFF (.tiff)", "tiff"),
            ("GIF (.gif)",   "gif")
        ]
        panel.allowedFileTypes = formats.map { $0.ext }

        // Accessory view
        let label = NSTextField(labelWithString: "File format:")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: formats.map { $0.title })
        for (i, f) in formats.enumerated() { popup.item(at: i)?.representedObject = f.ext }
        popup.target = self
        popup.action = #selector(saveAsFormatChanged(_:))

        // Preselect based on current extension and sync the name field if needed
        if let idx = formats.firstIndex(where: { $0.ext == defaultExt }) {
            popup.selectItem(at: idx)
            // Make sure the text field extension matches the selected item exactly
            replaceNameFieldExtension(in: panel, with: formats[idx].ext)
        } else {
            popup.selectItem(at: 0)
            replaceNameFieldExtension(in: panel, with: formats[0].ext)
        }

        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        panel.accessoryView = stack

        guard panel.runModal() == .OK, var url = panel.url else { return }

        // Enforce the selected extension on save, even if user typed something else
        let chosenExt = (popup.selectedItem?.representedObject as? String) ?? defaultExt
        if url.pathExtension.lowercased() != chosenExt {
            url.deletePathExtension()
            url.appendPathExtension(chosenExt)
        }

        currentDocumentURL = url
        doSave(to: url)
    }
    
    // NEW: Prompt before destructive actions (New / Open / Exit)
    @objc func fileNew(_ sender: Any?) {
        // If nothing to lose, just clear
        guard hasUnsavedChanges() else {
            currentDocumentURL = nil
            canvasView()?.clearCanvas()
            refreshBaselineSnapshot()
            return
        }

        askToKeepCurrentImage { choice in
            switch choice {
            case .delete:
                self.currentDocumentURL = nil
                self.canvasView()?.clearCanvas()
                self.refreshBaselineSnapshot()
            case .save:
                if self.performSaveAndReport() {
                    self.currentDocumentURL = nil
                    self.canvasView()?.clearCanvas()
                    self.refreshBaselineSnapshot()
                }
            case .cancel:
                break
            }
        }
    }

    @objc func fileOpen(_ sender: Any?) {
        let proceedToOpen = { [weak self] in
            guard let self = self else { return }
            self.showOpenPanelAndLoad()
        }

        guard hasUnsavedChanges() else {
            proceedToOpen()
            return
        }

        askToKeepCurrentImage { choice in
            switch choice {
            case .delete:
                proceedToOpen()
            case .save:
                if self.performSaveAndReport() {
                    proceedToOpen()
                }
            case .cancel:
                break
            }
        }
    }

    // Split out the actual Open… flow
    private func showOpenPanelAndLoad() {
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
            self?.refreshBaselineSnapshot()
        }
    }

    // Exit with prompt
    @objc func fileExit(_ sender: Any?) {
        // If nothing to lose, quit immediately
        guard hasUnsavedChanges() else {
            NSApp.terminate(sender)
            return
        }

        askToKeepCurrentImage { choice in
            switch choice {
            case .delete:
                NSApp.terminate(sender)
            case .save:
                if self.performSaveAndReport() {
                    NSApp.terminate(sender)
                }
            case .cancel:
                break
            }
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

    // MARK: - Save helper (used by plain Save)

    private func doSave(to url: URL) {
        guard let image = snapshotCanvas() ?? canvasView()?.canvasImage else { return }

        let ext = url.pathExtension.lowercased()
        let fileType: NSBitmapImageRep.FileType
        switch ext {
        case "png":  fileType = .png
        case "jpg", "jpeg": fileType = .jpeg
        case "bmp":  fileType = .bmp
        case "tiff": fileType = .tiff
        case "gif":  fileType = .gif
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
            // Refresh baseline now that the on-disk state matches the canvas
            self.refreshBaselineSnapshot()
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
    // Add this corrected version (converts rect to image space):
    private func currentSelectionImage(from canvas: CanvasView) -> NSImage? {
        if let img = canvas.selectedImage {
            return img
        }
        if let rect = canvas.selectionRect, let base = canvas.canvasImage {
            // Convert selection from canvas/view space to image space
            let imgRect = NSRect(
                x: rect.origin.x - canvas.canvasRect.origin.x,
                y: rect.origin.y - canvas.canvasRect.origin.y,
                width: rect.size.width,
                height: rect.size.height
            )
            let image = NSImage(size: rect.size)
            image.lockFocus()
            base.draw(
                in: NSRect(origin: .zero, size: rect.size),
                from: imgRect,
                operation: .copy,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.none]
            )
            image.unlockFocus()
            return image
        }
        return nil
    }
    
    // 1×, gutter-free PNG data of the canvas (flattened if there’s a floating selection)
    private func pngData1xFlattenedFromCanvas() -> Data? {
        guard let canvas = canvasView() else { return nil }

        // Build the flattened visual (base + floating selection), but DON'T write this image directly.
        // We'll draw it into a 1× bitmap with a flipped CG context.
        guard let flattened = canvas.snapshotImageForExport() else { return nil }

        // Exact canvas pixel size (no gutter, no zoom)
        let size = canvas.canvasRect.size
        let pw = Int(round(size.width))
        let ph = Int(round(size.height))
        guard pw > 0, ph > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pw,
            pixelsHigh: ph,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        // Ensure Finder reads 1pt == 1px
        rep.size = NSSize(width: pw, height: ph)

        NSGraphicsContext.saveGraphicsState()
        if let gctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = gctx

            // Fill background first (unflipped is fine for a solid fill)
            let cg = gctx.cgContext
            cg.setFillColor(NSColor.white.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: pw, height: ph))

            // 🔄 Flip the Y-axis so drawing lands upright in the PNG
            cg.translateBy(x: 0, y: CGFloat(ph))
            cg.scaleBy(x: 1, y: -1)

            // Now draw the flattened NSImage WITHOUT respecting flipped (we already flipped CG)
            flattened.draw(
                in: NSRect(x: 0, y: 0, width: CGFloat(pw), height: CGFloat(ph)),
                from: NSRect(origin: .zero, size: flattened.size),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.none]
            )

            gctx.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // Convenience snapshot that returns an NSImage at 1× canvas size (no gutter)
    private func snapshotCanvas() -> NSImage? {
        guard let canvas = canvasView() else { return nil }
        // Reuse the same flattened drawing used for PNG, but keep NSImage return
        guard let data = pngData1xFlattenedFromCanvas() else { return nil }
        return NSImage(data: data)
    }

    // Optional: a helper you can call from your Export/Save menu action
    @IBAction func exportPNG1x(_ sender: Any?) {
        guard let data = pngData1xFlattenedFromCanvas() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Untitled.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Help menu

    @objc private func showHelpTopics(_ sender: Any?) {
        presentHelpTopicsWindow()
    }

    @objc private func showAboutPaint(_ sender: Any?) {
        // Minimal, localized-friendly credits text
        let credits = NSAttributedString(
            string: "© 2025 Paint95 — Jeffrey McIntosh",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ]
        )

        // Use the standard About panel, but inject credits
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentHelpTopicsWindow() {
        // ---- Window first so we know an initial content width ----
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Help Topics"
        win.center()
        win.delegate = self

        // ---- Host view + scroll view ----
        let contentView = NSView()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        contentView.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // ---- Text view inside the scroll view ----
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)

        // Important: give the container a real width BEFORE layout,
        // otherwise it can stay 0 and nothing draws.
        let initialContentWidth = win.contentLayoutRect.width
        let containerWidth = max(360, initialContentWidth) // safety minimum
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: containerWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        // ---- Styles ----
        func pStyle(_ spacing: CGFloat = 2, _ after: CGFloat = 8) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = spacing
            p.paragraphSpacing = after
            return p
        }
        let h1: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: pStyle(2, 10)
        ]
        let h2: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: pStyle(1, 6)
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: pStyle()
        ]
        let monoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        func append(_ s: String, _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
            return NSAttributedString(string: s + "\n", attributes: attrs)
        }
        func bullet(_ s: String) -> NSAttributedString {
            return NSAttributedString(string: "• " + s + "\n", attributes: bodyAttrs)
        }

        // ---- Build content ----
        let body = NSMutableAttributedString()

        // Intro
        body.append(append("Welcome to Paint95 Help", h1))
        body.append(NSAttributedString(string:
            """
            Select a tool from the Tool Box, choose colours from the Colour Palette, and use menus to transform your image.
            Hold ⇧ to constrain lines to 45° and draw perfect squares/circles. Use the Select tool to move/resize pasted or selected regions.
            “Draw Opaque” controls whether white is treated as transparent when pasting.

            """, attributes: bodyAttrs))

        // Tools (full list)
        body.append(append("Tools", h1))
        [
            "Pencil — 1-pixel hard stroke.",
            "Brush — Variable-size soft stroke.",
            "Eraser — Paint with white to remove pixels.",
            "Fill (Bucket) — Flood-fill contiguous colour.",
            "Line — Straight line; ⇧ snaps to 45°.",
            "Rectangle — Outline; ⇧ for square.",
            "Rounded Rectangle — Rounded corners; ⇧ for square.",
            "Ellipse — Outline; ⇧ for circle.",
            "Curve — Start/end then two control clicks.",
            "Text — Type in a box; commits on exit.",
            "Select — Rectangular selection; move/resize; cut/copy/paste.",
            "Spray — Airbrush effect.",
            "Eyedropper — Pick colour from canvas.",
            "Zoom — Toggle a zoom box preview and magnified view."
        ].forEach { body.append(bullet($0)) }
        body.append(NSAttributedString(string: "\n", attributes: bodyAttrs))

        // Menus (dynamic; always matches the actual menu bar)
        body.append(append("Menus", h1))

        // Helper: human-friendly shortcut string (e.g. ⌘⇧S, Delete, ⌘,)
        func shortcutString(for item: NSMenuItem) -> String? {
            let key = item.keyEquivalent
            if key.isEmpty { return nil }

            func mods(_ m: NSEvent.ModifierFlags) -> String {
                var s = ""
                if m.contains(.command) { s += "⌘" }
                if m.contains(.shift)   { s += "⇧" }
                if m.contains(.option)  { s += "⌥" }
                if m.contains(.control) { s += "⌃" }
                return s
            }

            let mod = mods(item.keyEquivalentModifierMask)

            // Special keys we use in the app
            switch key {
            case "\u{8}":   return mod + "Delete"        // Backspace as Delete in menus
            case "\r":      return mod + "Return"
            case "\n":      return mod + "Enter"
            default:        break
            }

            // Uppercase letter if single a–z; otherwise show raw symbol (e.g. ",", "?", "0"…"9")
            if key.count == 1, let c = key.uppercased().first {
                return mod + String(c)
            }
            return mod + key
        }

        // Helper: description for a menu item (optional, lightweight)
        func describe(_ title: String) -> String? {
            // Common items (you can expand this map over time)
            switch title {
            case _ where title.hasPrefix("About "): return "Show app version and credits."
            case _ where title.hasPrefix("Hide "):  return "Hide this app."
            case "Hide Others": return "Hide all other apps."
            case "Show All": return "Reveal all hidden apps."
            case _ where title.hasPrefix("Quit "): return "Quit the application."

            case "New": return "Create a new blank canvas."
            case "Open…": return "Open an image file."
            case "Save": return "Save the current document."
            case "Save As…": return "Save to a new file."
            case "Send…": return "Share the image with another app."
            case "Set As Wallpaper (Tiled)": return "Set the image as a tiled desktop background."
            case "Set As Wallpaper (Centered)": return "Set the image as a centered desktop background."
            case "Exit": return "Close the window."

            case "Undo": return "Undo the last action."
            case "Repeat": return "Redo the last undone action."
            case "Cut": return "Cut the current selection."
            case "Copy": return "Copy the current selection."
            case "Paste": return "Paste from the clipboard."
            case "Clear Selection": return "Delete pixels in the current selection."
            case "Select All": return "Select the entire canvas."
            case "Set Canvas Size…": return "Change canvas width and height."
            case "Copy To…": return "Export the selection to a new file."
            case "Paste From…": return "Import from a file into the canvas."

            case "Tool Box": return "Show or hide the tool palette."
            case "Colour Box": return "Show or hide the colour palette."
            case "Status Bar": return "Show or hide the status strip."
            case "Zoom (activate tool)": return "Switch to the Zoom tool."
            case "Normal Size": return "Display at normal scale."
            case "Large Size": return "Display at larger scale."
            case "Custom…": return "Choose a custom zoom level."
            case "View Bitmap…": return "Inspect the raw bitmap."

            case "Flip/Rotate…": return "Flip or rotate the selection/canvas."
            case "Stretch/Skew…": return "Scale and shear the selection/canvas."
            case "Invert Colors": return "Invert pixel colours."
            case "Attributes…": return "View image properties."
            case "Clear Image": return "Erase the entire canvas."
            case "Draw Opaque": return "Treat white as solid when pasting."

            case "Colours…": return "Edit active colours and palettes."
            case "Get Colours…": return "Pick colours from system sources."
            case "Save Colours…": return "Save current palette to file."
            case "Restore Default Colours": return "Reset palette to defaults."

            case "Help Topics": return "Open this help window."
            case "About Paint": return "About dialog (alternate location)."
            default: return nil
            }
        }

        // Iterate menus in the exact order they appear in the menubar
        if let mainMenu = NSApp.mainMenu {
            for top in mainMenu.items {
                guard let submenu = top.submenu,
                      !submenu.items.isEmpty else { continue }

                body.append(append(submenu.title, h2))

                for item in submenu.items {
                    if item.isSeparatorItem { continue }
                    let title = item.title.isEmpty ? "—" : item.title
                    let shortcut = shortcutString(for: item).map { " (\($0))" } ?? ""

                    if let desc = describe(title) {
                        body.append(bullet("\(title)\(shortcut) — \(desc)"))
                    } else {
                        body.append(bullet("\(title)\(shortcut)"))
                    }
                }
                body.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
            }
        } else {
            // Fallback if no main menu (very unlikely after constructMenuBar())
            body.append(bullet("No menu loaded."))
        }

        // Put text into the text view
        textView.textStorage?.setAttributedString(body)

        // Ensure layout now and give the text view a real height so it is visible.
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            textView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: used.height + 24)
        } else {
            textView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: 1000)
        }

        // Hook up the scroll view
        scroll.documentView = textView

        // Show window
        win.contentView = contentView
        let wc = NSWindowController(window: win)
        self.helpTopicsWC = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // After the window lays out, update the container width once more so wrapping is correct on first show.
        DispatchQueue.main.async {
            let w = win.contentLayoutRect.width
            let width = max(360, w)
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = width
            if let lm = textView.layoutManager, let tc = textView.textContainer {
                lm.ensureLayout(for: tc)
                let used = lm.usedRect(for: tc)
                textView.frame.size.height = used.height + 24
            }
        }
    }
    
    // MARK: - Help content builder

    private func buildHelpAttributedString() -> NSAttributedString {
        let out = NSMutableAttributedString()

        // Styles
        let body = NSFont.systemFont(ofSize: 13)
        let h1   = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let h2   = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let basePara: NSParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 2
            p.paragraphSpacing = 6
            return p
        }()

        func addHeader(_ text: String, font: NSFont, topSpace: CGFloat = 12) {
            let p = (basePara.mutableCopy() as! NSMutableParagraphStyle)
            p.paragraphSpacingBefore = topSpace
            out.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: p
            ]))
        }

        func addBody(_ text: String) {
            out.append(NSAttributedString(string: text + "\n", attributes: [
                .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: basePara
            ]))
        }

        func addBullet(_ text: String) {
            let p = (basePara.mutableCopy() as! NSMutableParagraphStyle)
            p.headIndent = 18
            p.firstLineHeadIndent = 0
            p.tabStops = [NSTextTab(textAlignment: .left, location: 18)]
            out.append(NSAttributedString(string: "•\t" + text + "\n", attributes: [
                .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: p
            ]))
        }

        func kbd(_ s: String) -> NSAttributedString {
            return NSAttributedString(string: s, attributes: [
                .font: mono, .foregroundColor: NSColor.secondaryLabelColor
            ])
        }

        // --- Intro ---
        addHeader("Welcome to Paint95 Help", font: h1, topSpace: 0)
        addBody("""
    Select a tool from the Tool Box on the left, choose colours from the Colour Palette, and use menus for image operations and view options.
    """)
        addHeader("Tips", font: h2)
        [
            "Hold ⇧ to constrain lines to 45° steps and to draw perfect squares/circles.",
            "Use the Select tool to move/resize pasted or selected regions.",
            "“Draw Opaque” controls whether white is treated as transparent when pasting.",
            "Arrow keys nudge selections or pasted overlays; Return commits; Delete cancels paste or clears selection."
        ].forEach(addBullet)

        // --- Tools (complete list) ---
        addHeader("Tools", font: h1)
        for (name, desc) in allToolsHelp() {
            addBullet("\(name) — \(desc)")
        }

        // --- Menus (walk the real menu bar and explain each item) ---
        addHeader("Menus", font: h1)

        if let main = NSApp.mainMenu {
            for menuItem in main.items {
                guard let submenu = menuItem.submenu, !submenu.items.isEmpty else { continue }
                addHeader(menuItem.title, font: h2)

                for item in submenu.items where !(item.isSeparatorItem) {
                    let title = item.title.replacingOccurrences(of: "...", with: "…") // normalize
                    let shortcut = shortcutString(for: item)

                    // Explanation for this item
                    let expl = menuItemExplanation(forTitle: title)

                    // Compose line
                    var line = title
                    if !shortcut.isEmpty { line += " (\(shortcut))" }
                    line += " — \(expl)"

                    addBullet(line)
                }
            }
        } else {
            // Fallback if menu isn't initialized yet
            addBody("Menus will appear here once the application menu bar is available.")
        }

        // --- Keyboard Shortcuts quick legend ---
        addHeader("Keyboard Shortcuts", font: h1)
        out.append(kbd("""
    ⌘Z Undo    ⌘Y Redo    ⌘X Cut    ⌘C Copy    ⌘V Paste
    ⌘A Select All    Delete Clear selection/cancel paste
    Arrows Nudge selection/paste    Return Commit paste/selection
    """))

        return out
    }

    // All tools + one-line explanations (edit these to taste)
    private func allToolsHelp() -> [(String, String)] {
        return [
            ("Pencil", "Draws 1-pixel hard strokes without smoothing."),
            ("Brush", "Draws variable-width soft strokes (set via Tool Size)."),
            ("Eraser", "Erases to background and removes overlapping vector strokes."),
            ("Fill", "Flood-fills a contiguous region with the current colour."),
            ("Curve", "Three-stage curve: define line, then two control points."),
            ("Line", "Draw a straight line; hold ⇧ to snap to 45° increments."),
            ("Rectangle", "Draw a rectangle; hold ⇧ for a square."),
            ("Rounded Rectangle", "Rectangle with rounded corners."),
            ("Ellipse", "Draw an ellipse; hold ⇧ for a circle."),
            ("Zoom", "Toggle a zoom box preview and magnified view."),
            ("Select", "Marquee selection; drag handles to resize; move with mouse/arrow keys."),
            ("Spray", "Spray can effect within a radius at the cursor."),
            ("Eyedropper", "Pick a colour from the canvas."),
            ("Text", "Create a text box; commit to raster on finish.")
        ]
    }

    // Human-written explanations for every menu item title you ship.
    // Keys should match the actual visible titles in your menus.
    private func menuItemExplanation(forTitle title: String) -> String {
        let map: [String: String] = [
            // File
            "New": "Create a blank canvas.",
            "Open…": "Open an image file.",
            "Save": "Save the current document to its file.",
            "Save As…": "Save to a new file/format.",
            "Export Palette…": "Export the current palette (.gpl, JASC-PAL, or .clr).",
            "Import Palette…": "Import a palette file and replace the current palette.",
            "Close": "Close the current window.",
            // Edit
            "Undo": "Revert the last change (up to 5 steps).",
            "Redo": "Reapply the last undone change.",
            "Cut": "Remove selection from canvas and copy to clipboard.",
            "Copy": "Copy selection to clipboard (without removing it).",
            "Paste": "Paste from clipboard as a movable overlay; Return commits.",
            "Delete": "Clear selection or cancel paste overlay.",
            "Select All": "Select the entire canvas.",
            "Clear Selection": "Deselect and clear selection rectangle.",
            // Image
            "Flip/Rotate…": "Flip horizontally/vertically or rotate the selection/canvas.",
            "Stretch/Skew…": "Scale and skew the selection/canvas.",
            "Canvas Size…": "Change the canvas dimensions.",
            "Clear Canvas": "Erase the entire canvas to white.",
            // View
            "Zoom In": "Increase magnification.",
            "Zoom Out": "Decrease magnification.",
            "Show Grid": "Toggle grid overlay (if implemented).",
            "Draw Opaque": "When off, white acts as transparent during paste.",
            // Tools (menu items)
            "Tool Size": "Adjust the size for brush/eraser and some shapes.",
            "Primary Colour": "Set the primary drawing colour.",
            "Secondary Colour": "Set the secondary colour (background/fill).",
            // Help
            "Paint95 Help": "Open this Help Topics window.",
            "Keyboard Shortcuts": "List of common shortcuts.",
            "About Paint": "Show app information."
        ]

        // Return mapped explanation or a reasonable default
        return map[title] ?? "No description provided."
    }

    // Nicely formatted shortcut like "⌘Z", "⇧⌘S", or "" if none
    private func shortcutString(for item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var parts = [String]()
        if m.contains(.control)   { parts.append("⌃") }
        if m.contains(.option)    { parts.append("⌥") }
        if m.contains(.shift)     { parts.append("⇧") }
        if m.contains(.command)   { parts.append("⌘") }

        // Special arrows and delete/return if you use them as key equivalents
        let key = item.keyEquivalent.lowercased()
        let pretty: String = {
            switch key {
            case String(UnicodeScalar(NSUpArrowFunctionKey)!): return "↑"
            case String(UnicodeScalar(NSDownArrowFunctionKey)!): return "↓"
            case String(UnicodeScalar(NSLeftArrowFunctionKey)!): return "←"
            case String(UnicodeScalar(NSRightArrowFunctionKey)!): return "→"
            case "\r": return "↩" // Return
            case String(UnicodeScalar(NSDeleteFunctionKey)!): return "⌫"
            default: return key.uppercased()
            }
        }()
        parts.append(pretty)
        return parts.joined()
    }


    // Release retained Help Topics WC when closed
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === helpTopicsWC?.window {
            helpTopicsWC = nil
        }
    }

    // MARK: - Save/Discard prompt before destructive actions

    private enum DiscardChoice { case delete, save, cancel }

    // PNG snapshot of current canvas for change detection
    private func currentCanvasSnapshotPNG() -> Data? {
        guard let image = snapshotCanvas() ?? canvasView()?.canvasImage else { return nil }
        guard
            let tiff = image.tiffRepresentation,
            let rep  = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        return data
    }

    // Update the baseline to "no unsaved changes"
    private func refreshBaselineSnapshot() {
        self.lastSavedSnapshot = currentCanvasSnapshotPNG()
        self.window?.isDocumentEdited = false
    }

    // Returns true only if current canvas differs from the baseline
    private func hasUnsavedChanges() -> Bool {
        let now = currentCanvasSnapshotPNG()
        return now != lastSavedSnapshot
    }

    /// Present "Do you want to keep the current image?" with Delete (far left) / Cancel / Save (far right).
    private func askToKeepCurrentImage(completion handler: @escaping (DiscardChoice) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Do you want to keep the current image?"
        alert.informativeText = "If you delete, the current image will be lost."
        alert.alertStyle = .warning

        // Add in reverse so rightmost is Save (default), then Cancel, then far-left Delete
        let saveButton   = alert.addButton(withTitle: "Save")     // rightmost
        let cancelButton = alert.addButton(withTitle: "Cancel")   // middle-right
        _ = alert.addButton(withTitle: "Delete")                  // leftmost

        saveButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"

        let handle: (NSApplication.ModalResponse) -> Void = { resp in
            switch resp {
            case .alertFirstButtonReturn:  handler(.save)   // Save
            case .alertSecondButtonReturn: handler(.cancel) // Cancel
            case .alertThirdButtonReturn:  handler(.delete) // Delete
            default:                       handler(.cancel)
            }
        }

        if let w = self.window {
            alert.beginSheetModal(for: w, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    /// Kick off a save and report whether it appears to have completed (best-effort).
    private func performSaveAndReport() -> Bool {
        let hadURL = currentDocumentURL
        fileSave(nil) // may invoke Save As… synchronously in our implementation

        // If we didn't have a URL going in and still don't have one, assume cancelled.
        if hadURL == nil && currentDocumentURL == nil { return false }
        return true
    }

    // MARK: - Options menu actions (NEW)

    @objc func optionsSaveColours(_ sender: Any?) {
        guard let vc = vc() else { return }
        let colors = vc.colourPaletteView.colours   // 16 swatches

        let panel = NSSavePanel()
        panel.title = "Save Colours"
        panel.allowedFileTypes = ["gpl", "pal", "clr"]
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = "Palette.gpl"  // default suggestion

        guard panel.runModal() == .OK, var url = panel.url else { return }

        // Ensure file has an extension (default to .gpl if user omits)
        let ext = url.pathExtension.lowercased()
        let chosenExt: String = ext.isEmpty ? "gpl" : ext
        if ext.isEmpty {
            url.deletePathExtension()
            url.appendPathExtension(chosenExt)
        }

        do {
            switch chosenExt {
            case "gpl":
                try AppPaletteExporter.saveGPL(colors, to: url)
            case "pal":
                try AppPaletteExporter.saveJASCPAL(colors, to: url)
            case "clr":
                try AppPaletteExporter.saveCLR(colors, to: url)
            default:
                throw AppPaletteExporter.Error.unsupportedType
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Save Colours"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func optionsRestoreDefaultColours(_ sender: Any?) {
        // Broadcast the classic default 16; ColourPaletteView listens for .paletteLoaded.
        let defaults: [NSColor] = [
            .black, .darkGray, .gray, .white,
            .red, .green, .blue, .cyan,
            .yellow, .magenta, .orange, .brown,
            .systemPink, .systemIndigo, .systemTeal, .systemPurple
        ]
        NotificationCenter.default.post(name: .paletteLoaded, object: defaults)
    }
}

// MARK: - SaveFormat for Save As popup
private enum SaveFormat: CaseIterable, Equatable {
    // Order roughly matches classic Paint era
    case bmp, gif, jpeg, png, tiff

    var displayName: String {
        switch self {
        case .bmp:  return "BMP"
        case .gif:  return "GIF"
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .tiff: return "TIFF"
        }
    }
    var fileExtension: String {
        switch self {
        case .bmp:  return "bmp"
        case .gif:  return "gif"
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .tiff: return "tiff"
        }
    }
    var repType: NSBitmapImageRep.FileType {
        switch self {
        case .bmp:  return .bmp
        case .gif:  return .gif
        case .jpeg: return .jpeg
        case .png:  return .png
        case .tiff: return .tiff
        }
    }
}

private extension AppDelegate {
    func enforceSelectedExtension(on panel: NSSavePanel, selected: SaveFormat) -> URL {
        // Start from panel.url and append the selected extension
        // if the name field doesn't already end with it (case-insensitive).
        var url = panel.url!
        let nameLower = panel.nameFieldStringValue.lowercased()
        let dotExt = "." + selected.fileExtension.lowercased()
        if !nameLower.hasSuffix(dotExt) {
            url = url.appendingPathExtension(selected.fileExtension)
        }
        return url
    }
}

// MARK: - NSSavePanel accessory helpers
private extension AppDelegate {
    func makeSaveAsAccessory(for panel: NSSavePanel, initial: SaveFormat) -> NSView {
        let container = NSView(frame: .init(x: 0, y: 0, width: 360, height: 28))

        let label = NSTextField(labelWithString: "File format:")
        label.alignment = .right
        label.frame = .init(x: 0, y: 4, width: 90, height: 20)

        let popup = NSPopUpButton(frame: .init(x: 100, y: 1, width: 240, height: 26), pullsDown: false)
        popup.target = self
        popup.action = #selector(saveAsFormatChanged(_:))

        // Populate
        SaveFormat.allCases.enumerated().forEach { (i, fmt) in
            popup.addItem(withTitle: "\(fmt.displayName) (.\(fmt.fileExtension))")
            popup.item(at: i)?.tag = i
        }
        if let idx = SaveFormat.allCases.firstIndex(of: initial) {
            popup.selectItem(at: idx)
        }

        self.saveAsFormatPopup = popup
        container.addSubview(label)
        container.addSubview(popup)
        return container
    }

    @objc private func saveAsFormatChanged(_ sender: NSPopUpButton) {
        guard let panel = activeSaveAsPanel else { return }
        let ext = (sender.selectedItem?.representedObject as? String) ?? "png"
        replaceNameFieldExtension(in: panel, with: ext)
    }

    private func replaceNameFieldExtension(in panel: NSSavePanel, with newExt: String) {
        var name = panel.nameFieldStringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Untitled" }
        let base = (name as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + newExt
    }

    func selectedSaveAsFormat() -> SaveFormat? {
        guard let popup = saveAsFormatPopup else { return nil }
        let idx = popup.indexOfSelectedItem
        let all = SaveFormat.allCases
        guard idx >= 0 && idx < all.count else { return nil }
        return all[idx]
    }

    private func updateNameFieldExtension(on panel: NSSavePanel, toExt ext: String) {
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + ext
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

// MARK: - Local palette exporter (kept in this file to avoid external deps)
private enum AppPaletteExporter {
    enum Error: LocalizedError {
        case unsupportedType
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedType: return "Unsupported palette type."
            case .writeFailed(let why): return "Write failed: \(why)"
            }
        }
    }

    // GIMP .gpl
    static func saveGPL(_ colors: [NSColor], to url: URL) throws {
        var out = "GIMP Palette\nName: Paint95 Export\nColumns: 16\n#\n"
        for c in colors {
            let (r,g,b) = rgb255(c)
            out += String(format: "%3d %3d %3d\tColor\n", r, g, b)
        }
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw Error.writeFailed(error.localizedDescription)
        }
    }

    // JASC-PAL text
    static func saveJASCPAL(_ colors: [NSColor], to url: URL) throws {
        var out = "JASC-PAL\n0100\n\(colors.count)\n"
        for c in colors {
            let (r,g,b) = rgb255(c)
            out += "\(r) \(g) \(b)\n"
        }
        do {
            try out.write(to: url, atomically: true, encoding: .ascii)
        } catch {
            throw Error.writeFailed(error.localizedDescription)
        }
    }

    // Apple .clr
    static func saveCLR(_ colors: [NSColor], to url: URL) throws {
        let base = url.deletingPathExtension().lastPathComponent
        let name = NSColorList.Name(base.isEmpty ? "Paint95 Export" : base)
        let list = NSColorList(name: name)
        for (i, c) in colors.enumerated() {
            list.setColor(c.usingColorSpace(.deviceRGB) ?? c, forKey: "Color \(i+1)")
        }
        if !list.write(toFile: url.path) {
            throw Error.writeFailed("NSColorList write failed.")
        }
    }

    private static func rgb255(_ c: NSColor) -> (Int, Int, Int) {
        let d = c.usingColorSpace(.deviceRGB) ?? c
        let r = Int(round(d.redComponent   * 255))
        let g = Int(round(d.greenComponent * 255))
        let b = Int(round(d.blueComponent  * 255))
        return (max(0,min(255,r)), max(0,min(255,g)), max(0,min(255,b)))
    }
}

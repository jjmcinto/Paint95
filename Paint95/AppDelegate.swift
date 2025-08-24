// AppDelegate.swift
import Cocoa

private extension NSView {
    var descendants: [NSView] {
        subviews.flatMap { [$0] + $0.descendants }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow?
    private var currentDocumentURL: URL?

    // MARK: - App lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        constructMenuBar()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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

        // ===== Placeholders =====
        main.addItem(makeEmptyMenu(title: "Image"))
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


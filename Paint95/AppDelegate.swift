// AppDelegate.swift
import Cocoa

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
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.title = "Paint95"

        // Load storyboard VC
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let rootVC = storyboard.instantiateInitialController() as? NSViewController
            ?? ViewController()

        window?.contentViewController = rootVC
        window?.center()
        window?.makeKeyAndOrderFront(nil)
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
        // (Printing removed)
        addFile("Send…",          #selector(fileSend(_:)))
        addFile("Set As Wallpaper (Tiled)",    #selector(fileSetWallpaperTiled(_:)))
        addFile("Set As Wallpaper (Centered)", #selector(fileSetWallpaperCentered(_:)))
        fileMenu.addItem(NSMenuItem.separator())
        addFile("Exit",           #selector(fileExit(_:)))

        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Placeholders
        main.addItem(makeEmptyMenu(title: "Edit"))
        main.addItem(makeEmptyMenu(title: "View"))
        main.addItem(makeEmptyMenu(title: "Image"))
        main.addItem(makeEmptyMenu(title: "Options"))
        main.addItem(makeEmptyMenu(title: "Help"))

        NSApp.mainMenu = main
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
        // Folder chooser
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        // Name prompt
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

        // Overwrite confirm
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
}

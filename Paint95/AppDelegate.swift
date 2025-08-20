// AppDelegate.swift
import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // If you use a storyboard window, this will be set automatically by AppKit
    // (we don't rely on it for logic below).
    var window: NSWindow?

    // Track where "Save" should write (so Save vs Save As behaves correctly)
    private var currentDocumentURL: URL?

    // Reuse across Page Setup / Print
    private var sharedPrintInfo = NSPrintInfo.shared

    // MARK: - App lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Ensure we own the menu bar before storyboard could inject one.
        constructMenuBar()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // In storyboard setups this usually already exists. If you create your
        // window in code, you can init it here. Either way, (re)build menu.
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

        // Load the storyboard's initial ViewController
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let rootVC = storyboard.instantiateInitialController() as? NSViewController
            ?? ViewController() // fallback if storyboard isn’t set as initial

        window?.contentViewController = rootVC
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu bar

    private func constructMenuBar() {
        let main = NSMenu()

        // ===== App (Paint95) menu =====
        let appName = ProcessInfo.processInfo.processName
        let appItem = NSMenuItem()
        main.addItem(appItem)

        let appMenu = NSMenu(title: appName)

        // About
        let about = NSMenuItem(
            title: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)

        appMenu.addItem(NSMenuItem.separator())

        // Hide / Hide Others / Show All
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

        // Quit
        let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)

        appItem.submenu = appMenu

        // ===== File menu =====
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
        addFile("Print Preview",  #selector(filePrintPreview(_:)))
        addFile("Page Setup…",    #selector(filePageSetup(_:)))
        addFile("Print…",         #selector(filePrint(_:)),     "p", [.command])
        fileMenu.addItem(NSMenuItem.separator())
        addFile("Send…",          #selector(fileSend(_:)))
        addFile("Set As Wallpaper (Tiled)",    #selector(fileSetWallpaperTiled(_:)))
        addFile("Set As Wallpaper (Centered)", #selector(fileSetWallpaperCentered(_:)))
        fileMenu.addItem(NSMenuItem.separator())
        addFile("Exit",           #selector(fileExit(_:)))

        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // ===== Edit menu (placeholder) =====
        main.addItem(makeEmptyMenu(title: "Edit"))

        // ===== View menu (placeholder) =====
        main.addItem(makeEmptyMenu(title: "View"))

        // ===== Image menu (placeholder) =====
        main.addItem(makeEmptyMenu(title: "Image"))

        // ===== Options menu (placeholder) =====
        main.addItem(makeEmptyMenu(title: "Options"))

        // ===== Help menu (placeholder) =====
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
        // Prefer key window first
        if let vc = NSApp.keyWindow?.contentViewController as? ViewController {
            return vc.canvasView
        }
        // Fallback: search all app windows
        for w in NSApp.windows {
            if let vc = w.contentViewController as? ViewController {
                return vc.canvasView
            }
        }
        return nil
    }

    @MainActor
    @IBAction func fileSave(_ sender: Any?) {
        guard let canvas = findCanvasView() else {
            NSSound.beep()
            print("Save: CanvasView not found.")
            return
        }
        print("Saving!")
        canvas.saveCanvasToDefaultLocation()
    }
    
    @objc func fileNew(_ sender: Any?) {
        currentDocumentURL = nil
        canvasView()?.clearCanvas()            // resets to blank white, same size
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

            // Replace canvas with opened image (classic Paint behavior)
            canvas.canvasImage = image.copy() as? NSImage
            canvas.canvasRect = NSRect(origin: .zero, size: image.size)
            canvas.updateCanvasSize(to: image.size)
            canvas.needsDisplay = true

            self?.currentDocumentURL = url
        }
    }
    
    @MainActor
    @IBAction func fileSaveAs(_ sender: Any?) {
        fileSave(sender) // temporary: same behavior as Save
    }

    @objc func filePageSetup(_ sender: Any?) {
        guard let win = NSApp.keyWindow else { return }
        let layout = NSPageLayout()
        layout.beginSheet(with: sharedPrintInfo, modalFor: win, delegate: nil, didEnd: nil, contextInfo: nil)
    }

    @objc func filePrint(_ sender: Any?) {
        guard let canvas = canvasView() else { return }
        let op = NSPrintOperation(view: canvas, printInfo: sharedPrintInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    @objc func filePrintPreview(_ sender: Any?) {
        // macOS typically previews via the Print panel
        filePrint(sender)
    }

    @objc func fileSend(_ sender: Any?) {
        NSSound.beep()
        print("Send… not implemented yet")
    }

    @objc func fileSetWallpaperTiled(_ sender: Any?) {
        NSSound.beep()
        print("Set As Wallpaper (Tiled) not implemented yet")
    }

    @objc func fileSetWallpaperCentered(_ sender: Any?) {
        NSSound.beep()
        print("Set As Wallpaper (Centered) not implemented yet")
    }

    @objc func fileExit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    // MARK: - Save helper

    private func doSave(to url: URL) {
        // Prefer a live snapshot (includes selection overlays etc.),
        // fall back to the stored canvas image
        guard let image = snapshotCanvas() ?? canvasView()?.canvasImage else { return }

        let ext = url.pathExtension.lowercased()
        let fileType: NSBitmapImageRep.FileType
        let props: [NSBitmapImageRep.PropertyKey: Any] = [:]

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
            let data = rep.representation(using: fileType, properties: props)
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

    /// Snapshot the current canvas rendering
    private func snapshotCanvas() -> NSImage? {
        guard let canvas = canvasView() else { return nil }
        // Prefer intrinsic size (CanvasView reports canvasRect.size); fallback to bounds
        let size = canvas.intrinsicContentSize == .zero ? canvas.bounds.size : canvas.intrinsicContentSize
        let bounds = NSRect(origin: .zero, size: size)
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        canvas.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}


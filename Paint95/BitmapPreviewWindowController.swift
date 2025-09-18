// BitmapPreviewWindowController.swift
import Cocoa

final class BitmapPreviewWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?

    init(image: NSImage) {
        // 1× image view
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleNone

        // Scroll view wrapper
        let initialSize = NSSize(width: min(900, image.size.width + 40),
                                 height: min(700, image.size.height + 40))
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: initialSize))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = imageView

        // Window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bitmap Preview"
        window.contentView = scroll

        // IMPORTANT: don’t auto-release on close; AppDelegate retains & drops us explicitly
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

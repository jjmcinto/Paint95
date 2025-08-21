// ColourMapView.swift
import AppKit

final class ColourMapView: NSView {
    weak var delegate: ColourPaletteDelegate?

    private var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        image = ColourMapProvider.loadImage()

        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)

        // Prefer the palette’s native size
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        if let img = image { return img.size }
        return ColourMapProvider.mapSize
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        guard let img = image else { return }
        img.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: img.size),
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    // MARK: - Picking (sample exactly what’s on screen)
    override func mouseDown(with event: NSEvent) {
        pick(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        pick(at: convert(event.locationInWindow, from: nil))
    }

    private func pick(at localPoint: NSPoint) {
        guard let c = sampledColour(at: localPoint) else { return }
        delegate?.colourSelected(c)
    }

    private func sampledColour(at viewPoint: NSPoint) -> NSColor? {
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Capture the actual rendered pixels of this view (handles Retina & scaling)
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)

        // Map view coords -> bitmap pixel coords
        let scaleX = CGFloat(rep.pixelsWide) / bounds.width
        let scaleY = CGFloat(rep.pixelsHigh) / bounds.height

        let px = Int((viewPoint.x * scaleX).rounded(.down))
        // NSBitmapImageRep’s (0,0) is bottom-left; our view is flipped (y=0 top),
        // so convert accordingly.
        let py = Int((viewPoint.y * scaleY).rounded(.down))

        guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
              let c = rep.colorAt(x: px, y: py) else { return nil }

        return c.usingColorSpace(.deviceRGB)
    }
}

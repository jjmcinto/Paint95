// ColourMapView.swift
import AppKit

protocol ColourMapViewDelegate: AnyObject {
    func colourMapView(_ view: ColourMapView, didPick colour: NSColor)
}

final class ColourMapView: NSView {
    weak var delegate: ColourMapViewDelegate?

    private var image: NSImage? {
        didSet { needsDisplay = true }
    }

    // If you want y=0 at top to match typical palettes:
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

        // Track in visible rect so we don't need to update when bounds change
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
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

        // Draw the palette to fill our bounds
        img.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: img.size),
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard let img = image else { return }
        let local = convert(event.locationInWindow, from: nil)
        let pixelPoint = mapToImagePixel(localPoint: local, image: img)
        guard let picked = ColourMapProvider.colour(at: pixelPoint, in: img) else { return }
        delegate?.colourMapView(self, didPick: picked)
    }

    private func mapToImagePixel(localPoint: NSPoint, image: NSImage) -> NSPoint {
        // Map a point in our view to the corresponding pixel in the image.
        let sx = image.size.width / bounds.width
        let sy = image.size.height / bounds.height
        let x = localPoint.x * sx
        let y = localPoint.y * sy
        return NSPoint(x: x, y: y)
    }
}

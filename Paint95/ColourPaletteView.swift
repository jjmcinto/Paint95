// ColourPaletteView.swift
import Cocoa

protocol ColourPaletteDelegate: AnyObject {
    func colourSelected(_ colour: NSColor)
}

final class ColourPaletteView: NSView {
    weak var delegate: ColourPaletteDelegate?

    /// The colour currently “active” in the palette (not drawn specially here).
    var selectedColour: NSColor = .black {
        didSet { needsDisplay = true }
    }

    /// Two-row (8×2) palette backing store. Always kept at exactly 16 entries.
    private(set) var colours: [NSColor] = ColourPaletteView.defaultPalette {
        didSet { needsDisplay = true }
    }

    private static let defaultPalette: [NSColor] = [
        .black, .darkGray, .gray, .white,
        .red, .green, .blue, .cyan,
        .yellow, .magenta, .orange, .brown,
        .systemPink, .systemIndigo, .systemTeal, .systemPurple
    ]

    // MARK: - Layout constants (shared by draw & hit-testing)
    private let kSquareSize = NSSize(width: 20, height: 20)
    private let kGap: CGFloat = 2
    private let kCols = 8
    private let kRows = 2
    private var kMaxCount: Int { kCols * kRows }

    private func rectForIndex(_ index: Int) -> NSRect {
        let col = index % kCols
        let row = index / kCols
        let x = CGFloat(col) * (kSquareSize.width + kGap)
        let y = CGFloat(row) * (kSquareSize.height + kGap)
        return NSRect(x: x, y: y, width: kSquareSize.width, height: kSquareSize.height)
    }

    /// Returns the swatch index for a point, or nil if the point is in a gap/background.
    private func swatchIndex(at point: NSPoint) -> Int? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let cellW = kSquareSize.width + kGap
        let cellH = kSquareSize.height + kGap
        let col = Int(point.x / cellW)
        let row = Int(point.y / cellH)
        let idx = row * kCols + col
        guard (0..<min(kMaxCount, colours.count)).contains(idx) else { return nil }
        // Ensure the click is inside the actual swatch rect (not the gap)
        return rectForIndex(idx).contains(point) ? idx : nil
    }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Update the strip whenever a new palette is imported.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onPaletteLoaded(_:)),
                                               name: .paletteLoaded,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Ensure exactly 16 items for a tidy 8×2 grid.
        let items = paddedPalette(Array(colours.prefix(kMaxCount)), to: kMaxCount)

        for (index, colour) in items.enumerated() {
            let rect = rectForIndex(index)

            // Uniform 1px grid border for all swatches
            NSColor.black.setStroke()
            NSBezierPath(rect: rect).stroke()

            // Fill INSIDE the stroke so black/white don’t look double-thick
            colour.setFill()
            rect.insetBy(dx: 1, dy: 1).fill()
        }
    }

    // MARK: - Mouse (hit-test only the swatches; ignore gaps/background)

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let idx = swatchIndex(at: p) else { return }
        let items = paddedPalette(Array(colours.prefix(kMaxCount)), to: kMaxCount)
        let colour = items[idx]
        selectedColour = colour
        delegate?.colourSelected(colour)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let idx = swatchIndex(at: p) else { return }
        let items = paddedPalette(Array(colours.prefix(kMaxCount)), to: kMaxCount)
        let colour = items[idx]
        selectedColour = colour
        delegate?.colourSelected(colour)
    }

    // MARK: - Palette import hook

    @objc private func onPaletteLoaded(_ note: Notification) {
        guard let cols = note.object as? [NSColor], !cols.isEmpty else { return }
        // Keep the palette at exactly 16 swatches (8×2 grid). Pad with white if needed.
        colours = paddedPalette(cols, to: 16)
    }

    private func paddedPalette(_ input: [NSColor], to count: Int) -> [NSColor] {
        if input.count >= count { return Array(input.prefix(count)) }
        return input + Array(repeating: .white, count: count - input.count)
    }
}

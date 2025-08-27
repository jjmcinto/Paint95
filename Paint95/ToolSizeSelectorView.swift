// ToolSizeSelectorView.swift
import Cocoa

protocol ToolSizeSelectorDelegate: AnyObject {
    func toolSizeSelected(_ size: CGFloat)
}

class ToolSizeSelectorView: NSView {
    weak var delegate: ToolSizeSelectorDelegate?

    /// Brush sizes in *pixels*. Circles are drawn at this diameter (clamped to fit the cell).
    let sizes: [CGFloat] = [1, 3, 5, 7, 9]

    /// Currently selected size (in px).
    var selectedSize: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    // Layout tuning
    private let vPad: CGFloat = 4        // vertical padding inside each cell
    private let hPad: CGFloat = 6        // horizontal padding inside each cell
    private let cellSpacing: CGFloat = 8 // spacing between cells (visual breathing room)

    deinit {
        print("ToolSizeSelectorView deinitialized")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        guard !sizes.isEmpty else { return }

        // Compute per-cell width with spacing
        let totalSpacing = cellSpacing * CGFloat(max(0, sizes.count - 1))
        let cellW = max(28, floor((bounds.width - totalSpacing) / CGFloat(sizes.count)))
        let cellH = bounds.height

        for (i, size) in sizes.enumerated() {
            let x0 = CGFloat(i) * (cellW + cellSpacing)
            let cell = NSRect(x: x0, y: 0, width: cellW, height: cellH)

            // Cell background (subtle)
            NSColor.controlBackgroundColor.setFill()
            cell.fill()

            // Selection ring
            if abs(size - selectedSize) < 0.5 {
                NSColor.controlAccentColor.setStroke()
                let ring = cell.insetBy(dx: 1, dy: 1)
                let ringPath = NSBezierPath(roundedRect: ring, xRadius: 4, yRadius: 4)
                ringPath.lineWidth = 2
                ringPath.stroke()
            }

            // Circle diameter = brush size (clamped to fit comfortably)
            let maxDia = max(1, min(size, min(cellH - 2*vPad, cellW - 2*hPad)))
            let circle = NSRect(
                x: cell.midX - maxDia/2,
                y: cell.midY - maxDia/2,
                width: maxDia,
                height: maxDia
            )

            // Draw the dot
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: circle).fill()

            // Thin outline for contrast on light backgrounds
            NSColor.separatorColor.setStroke()
            let outline = NSBezierPath(ovalIn: circle)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    // Click or drag selects nearest cell
    override func mouseDown(with event: NSEvent) { select(at: event) }
    override func mouseDragged(with event: NSEvent) { select(at: event) }

    private func select(at event: NSEvent) {
        guard !sizes.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)

        let totalSpacing = cellSpacing * CGFloat(max(0, sizes.count - 1))
        let cellW = max(28, floor((bounds.width - totalSpacing) / CGFloat(sizes.count)))

        // Map X to index considering spacing
        let span = cellW + cellSpacing
        var idx = Int(floor(p.x / span))
        // Clicks within a cell's width choose that cell; clamp to valid range
        idx = max(0, min(idx, sizes.count - 1))

        let newSize = sizes[idx]
        if abs(newSize - selectedSize) >= 0.5 {
            selectedSize = newSize
            delegate?.toolSizeSelected(newSize)
        }
        needsDisplay = true
    }
}

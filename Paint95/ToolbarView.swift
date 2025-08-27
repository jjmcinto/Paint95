// ToolbarView.swift
import Cocoa

// MARK: - Friendly names for hover/AX
extension PaintTool {
    var displayName: String {
        switch self {
        case .select:      return "Select"
        case .pencil:      return "Pencil"
        case .brush:       return "Brush"
        case .eraser:      return "Eraser"
        case .fill:        return "Fill"
        case .line:        return "Line"
        case .rect:        return "Rectangle"
        case .roundRect:   return "Rounded Rectangle"
        case .ellipse:     return "Ellipse"
        case .curve:       return "Curve"
        case .text:        return "Text"
        case .spray:       return "Spray"
        case .eyeDropper:  return "Eye Dropper"
        case .zoom:        return "Zoom"
        }
    }
}

// MARK: - Delegate
protocol ToolbarDelegate: AnyObject {
    func toolSelected(_ tool: PaintTool)
}

// MARK: - ToolbarView
final class ToolbarView: NSView {

    weak var delegate: ToolbarDelegate?

    // Layout constants for the grid
    private let cellSize: CGFloat = 40
    private let columns: Int = 2
    private let spacing: CGFloat = 0

    // Tool ordering (top-to-bottom, left-to-right)
    private let tools: [PaintTool] = [
        .pencil, .brush, .eraser, .fill, .text,
        .line, .curve, .rect, .ellipse, .roundRect,
        .eyeDropper, .select, .zoom, .spray
    ]

    // Mapping to image asset names (fallback text if missing)
    private let toolIcons: [PaintTool: String] = [
        .pencil: "pencil",
        .brush: "brush",
        .curve: "curve",
        .eraser: "eraser",
        .line: "line",
        .rect: "rect",
        .ellipse: "ellipse",
        .fill: "fill",
        .roundRect: "roundRect",
        .select: "select",
        .text: "text",
        .eyeDropper: "eyeDropper",
        .zoom: "zoom",
        .spray: "spray"
    ]

    // Selection index (nil = none)
    private var selectedToolIndex: Int? = nil

    // Tooltip bookkeeping
    private var tooltipTagByIndex: [Int: NSView.ToolTipTag] = [:]
    private var indexByTooltipTag: [NSView.ToolTipTag: Int] = [:]

    // MARK: Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(toolChanged(_:)),
                                               name: .toolChanged,
                                               object: nil)
        rebuildTooltips()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(toolChanged(_:)),
                                               name: .toolChanged,
                                               object: nil)
        rebuildTooltips()
    }

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(toolChanged(_:)),
                                               name: .toolChanged,
                                               object: nil)
        // tooltips built in awakeFromNib
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Keep tooltips aligned if the view resizes
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildTooltips()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor(white: 0.9, alpha: 1.0).setFill()
        bounds.fill()

        for (index, tool) in tools.enumerated() {
            let frame = frameForTool(at: index)

            // Highlight current selection
            if index == selectedToolIndex {
                NSColor.selectedControlColor.setStroke()
                let path = NSBezierPath(rect: frame)
                path.lineWidth = 2
                path.stroke()
            }

            // Draw icon or fallback label
            if let imageName = toolIcons[tool], let image = NSImage(named: imageName) {
                image.draw(in: frame)
            } else {
                let label = NSString(string: tool.displayName)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.black
                ]
                let textSize = label.size(withAttributes: attributes)
                let labelOrigin = NSPoint(
                    x: frame.midX - textSize.width / 2,
                    y: frame.midY - textSize.height / 2
                )
                label.draw(at: labelOrigin, withAttributes: attributes)
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let index = indexForPoint(p)
        guard tools.indices.contains(index) else { return }

        let tool = tools[index]
        selectedToolIndex = index
        delegate?.toolSelected(tool)
        needsDisplay = true
    }

    // MARK: Notifications

    @objc private func toolChanged(_ notification: Notification) {
        guard let newTool = notification.object as? PaintTool else { return }
        if let index = tools.firstIndex(of: newTool) {
            selectedToolIndex = index
            needsDisplay = true
        }
    }

    // MARK: Layout helpers

    private func frameForTool(at index: Int) -> NSRect {
        let row = index / columns
        let col = index % columns
        let x = CGFloat(col) * (cellSize + spacing)
        let y = CGFloat(row) * (cellSize + spacing)
        return NSRect(x: x, y: y, width: cellSize, height: cellSize)
    }

    private func indexForPoint(_ p: NSPoint) -> Int {
        let col = Int(p.x / (cellSize + spacing))
        let row = Int(p.y / (cellSize + spacing))
        return row * columns + col
    }

    // MARK: Tooltips

    private func rebuildTooltips() {
        // Clear old tooltips
        for (_, tag) in tooltipTagByIndex { removeToolTip(tag) }
        removeAllToolTips()
        tooltipTagByIndex.removeAll()
        indexByTooltipTag.removeAll()

        // Install a tooltip rect for each tool
        for i in tools.indices {
            let rect = frameForTool(at: i)
            let tag = addToolTip(rect, owner: self, userData: nil)
            tooltipTagByIndex[i] = tag
            indexByTooltipTag[tag] = i
        }
    }

    /// Provide the tooltip string (NSView tooltip owner callback)
    @objc func view(_ view: NSView,
                    stringForToolTip tag: NSView.ToolTipTag,
                    point: NSPoint,
                    userData data: UnsafeMutableRawPointer?) -> String
    {
        guard let index = indexByTooltipTag[tag], tools.indices.contains(index) else { return "" }
        return tools[index].displayName
    }
}


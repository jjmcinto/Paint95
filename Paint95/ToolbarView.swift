// ToolbarView.swift
import Cocoa

var selectedToolIndex: Int? = nil

protocol ToolbarDelegate: AnyObject {
    func toolSelected(_ tool: PaintTool)
}

class ToolbarView: NSView {
    weak var delegate: ToolbarDelegate?

    let tools: [PaintTool] = [
        .pencil, .brush, .eraser, .fill, .text,
        .line, .curve, .rect, .ellipse, .roundRect,
        .eyeDropper, .select, .zoom, .spray
    ]
    
    let toolIcons: [PaintTool: String] = [
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
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(toolChanged(_:)),
                                               name: .toolChanged,
                                               object: nil)
    }
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(toolChanged(_:)),
                                               name: .toolChanged,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func toolChanged(_ notification: Notification) {
        guard let newTool = notification.object as? PaintTool else { return }
        if let index = tools.firstIndex(of: newTool) {
            selectedToolIndex = index
            setNeedsDisplay(bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let cellSize: CGFloat = 40
        let columns = 2
        let spacing: CGFloat = 0
        
        NSColor(white: 0.9, alpha: 1.0).setFill()
        bounds.fill()
        
        for (index, tool) in tools.enumerated() {
            let row = index / columns
            let column = index % columns

            let x = CGFloat(column) * (cellSize + spacing)
            let y = CGFloat(row) * (cellSize + spacing)
            let frame = NSRect(x: x, y: y, width: cellSize, height: cellSize)

            // Draw highlight if selected
            if index == selectedToolIndex {
                NSColor.selectedControlColor.setStroke()
                let path = NSBezierPath(rect: frame)
                path.lineWidth = 2
                path.stroke()
            }
            
            // Load image for tool
            if let imageName = toolIcons[tool], let image = NSImage(named: imageName) {
                image.draw(in: frame)
            } else {
                // Fallback text if image is missing
                let label = NSString(string: "\(tool)")
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

    override func mouseDown(with event: NSEvent) {
        Swift.print("🛠️ ToolbarView mouseDown at:", convert(event.locationInWindow, from: nil))
        let locationInView = convert(event.locationInWindow, from: nil)
        let cellSize: CGFloat = 40
        let columns = 2

        let column = Int(locationInView.x / cellSize)
        let row = Int(locationInView.y / cellSize)
        let index = row * columns + column
        
        if tools.indices.contains(index) {
            let tool = tools[index]
            Swift.print("🛠️ select tool:", tool)
            selectedToolIndex = index
            delegate?.toolSelected(tool)
            setNeedsDisplay(bounds)
        }
    }
}

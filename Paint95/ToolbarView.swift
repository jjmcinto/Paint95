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
        .eyeDropper, .select, .zoom
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
        .eyeDropper: "eyeDropper"
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // You can draw backgrounds or borders here if desired
        
        let cellSize: CGFloat = 40
        let columns = 2
        let spacing: CGFloat = 0
        
        NSColor(white: 0.9, alpha: 1.0).setFill()
        let fillRect = self.bounds
        NSColor(white: 0.9, alpha: 1.0).setFill()
        fillRect.fill()
        
        for (index, tool) in tools.enumerated() {
            let row = index / columns
            let column = index % columns

            let x = CGFloat(column) * (cellSize + spacing)
            let y = CGFloat(row) * (cellSize + spacing)
            let frame = NSRect(x: x, y: y, width: cellSize, height: cellSize)

            // Draw a highlight if selected
            if index == selectedToolIndex {
                NSColor.selectedControlColor.setStroke()
                let path = NSBezierPath(rect: frame)
                path.lineWidth = 2
                path.stroke()
            }
            
            // 🔄 Load image from dictionary
            if let imageName = toolIcons[tool], let image = NSImage(named: imageName) {
                image.draw(in: frame)
            } else {
                // ✏️ Fallback label if image is missing
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
        let locationInView = convert(event.locationInWindow, from: nil)
        let cellSize: CGFloat = 40
        let columns = 2

        let column = Int(locationInView.x / cellSize)
        let row = Int(locationInView.y / cellSize)
        let index = row * columns + column

        if tools.indices.contains(index) {
            let tool = tools[index]
            selectedToolIndex = index
            delegate?.toolSelected(tool)
            setNeedsDisplay(bounds) // Refresh the toolbar to highlight selection
        }
    }
}


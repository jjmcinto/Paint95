// ToolbarView.swift
import Cocoa

protocol ToolbarDelegate: AnyObject {
    func toolSelected(_ tool: PaintTool)
}

class ToolbarView: NSView {
    weak var delegate: ToolbarDelegate?

    let tools: [PaintTool] = [
        .pencil, .brush, .eraser, .fill, .text,
        .line, .curve, .rectangle, .ellipse, .roundRect,
        .colorPicker, .select, .zoom
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // You can draw backgrounds or borders here if desired
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let toolHeight: CGFloat = 30
        let index = Int(point.y / toolHeight)
        if tools.indices.contains(index) {
            delegate?.toolSelected(tools[index])
        }
    }
}

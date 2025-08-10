// ToolSizeSelectorView.swift
import Cocoa

protocol ToolSizeSelectorDelegate: AnyObject {
    func toolSizeSelected(_ size: CGFloat)
}

class ToolSizeSelectorView: NSView {
    //@IBOutlet weak var delegate: ToolSizeSelectorDelegate?
    weak var delegate: ToolSizeSelectorDelegate?
    //var delegate: ToolSizeSelectorDelegate?
    var retainedSelf: ToolSizeSelectorView?

    let sizes: [CGFloat] = [1, 3, 5, 7, 9]
    var selectedSize: CGFloat = 1
    
    deinit {
        print("ToolSizeSelectorView deinitialized")
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
        print("ToolSizeSelectorView removed from superview")
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        retainedSelf = self  // Retaining reference during debug
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let buttonWidth: CGFloat = bounds.width / CGFloat(sizes.count)
        let buttonHeight: CGFloat = bounds.height

        for (i, size) in sizes.enumerated() {
            let x = CGFloat(i) * buttonWidth
            let rect = NSRect(x: x, y: 0, width: buttonWidth, height: buttonHeight)

            // Draw background
            if size == selectedSize {
                NSColor.selectedControlColor.setFill()
            } else {
                NSColor(white: 0.9, alpha: 1.0).setFill()
            }
            rect.fill()

            // Draw size indicator circle
            NSColor.black.setFill()
            let dotSize = size
            let dotRect = NSRect(
                x: rect.midX - dotSize/2,
                y: rect.midY - dotSize/2,
                width: dotSize,
                height: dotSize
            )
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
    
    // Ensure mouse events are handled properly and routed to the view
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let buttonWidth: CGFloat = bounds.width / CGFloat(sizes.count)
        let index = Int(location.x / buttonWidth)
        
        if sizes.indices.contains(index) {
            selectedSize = sizes[index]
            
            delegate?.toolSizeSelected(selectedSize)
            
            /*
            // Directly access the ViewController's method to handle the tool size change
            if let controller = self.window?.windowController as? ViewController {
                print("Directly calling toolSizeSelected: \(selectedSize)")
                controller.toolSizeSelected(selectedSize)  // Directly invoke method in ViewController
            }
            else {
                print("controller not defined!")
            }
            */

            setNeedsDisplay(bounds)
        }
    }
}

// ViewController.swift
import Cocoa  // ✅ Import AppKit for NSViewController, NSColor, etc.

class ViewController: NSViewController, ToolbarDelegate, ColorPaletteDelegate, CanvasViewDelegate {

    @IBOutlet weak var canvasView: CanvasView!
    @IBOutlet weak var toolbarView: ToolbarView!
    @IBOutlet weak var colorPaletteView: ColorPaletteView!
    @IBOutlet weak var colorSwatchView: ColorSwatchView!

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(updateColorSwatch(_:)), name: .colorPicked, object: nil)
        
        toolbarView.delegate = self
        colorPaletteView.delegate = self
        canvasView.delegate = self
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
           guard let self = self else { return event }
           return self.handleGlobalKeyDown(event)
       }
    }
    
    func handleGlobalKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
            case 51: // DELETE
                canvasView.handleDeleteKey()
                return nil
            case 123: // ←
                canvasView.moveSelectionBy(dx: -1, dy: 0)
                return nil
            case 124: // →
                canvasView.moveSelectionBy(dx: 1, dy: 0)
                return nil
            case 125: // ↓
                canvasView.moveSelectionBy(dx: 0, dy: -1)
                return nil
            case 126: // ↑
                canvasView.moveSelectionBy(dx: 0, dy: 1)
                return nil
            default:
                return event
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 { // 51 = Delete key
            canvasView.deleteSelectionOrPastedImage()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func updateColorSwatch(_ notification: Notification) {
        if let color = notification.object as? NSColor {
            colorSwatchView.color = color
        }
    }

    // MARK: - ToolbarDelegate
    func toolSelected(_ tool: PaintTool) {
        canvasView.currentTool = tool
    }

    // MARK: - ColorPaletteDelegate
    func colorSelected(_ color: NSColor) {
        canvasView.currentColor = color
        colorSwatchView.color = color
    }
    
    // Optional: Clear button or menu action
    @IBAction func clearCanvas(_ sender: Any) {
        canvasView.clearCanvas()
    }
    func didPickColor(_ color: NSColor) {
        canvasView.currentColor = color
        colorPaletteView.selectedColor = color
        colorPaletteView.needsDisplay = true
        colorSwatchView.color = color
    }
}

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

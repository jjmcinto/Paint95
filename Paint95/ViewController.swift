// ViewController.swift
import Cocoa  // ✅ Import AppKit for NSViewController, NSColor, etc.

class ViewController: NSViewController, ToolbarDelegate, ColorPaletteDelegate {

    @IBOutlet weak var canvasView: CanvasView!
    @IBOutlet weak var toolbarView: ToolbarView!
    @IBOutlet weak var colorPaletteView: ColorPaletteView!

    override func viewDidLoad() {
        super.viewDidLoad()
        toolbarView.delegate = self
        colorPaletteView.delegate = self
    }

    // MARK: - ToolbarDelegate
    func toolSelected(_ tool: PaintTool) {
        canvasView.currentTool = tool
    }

    // MARK: - ColorPaletteDelegate
    func colorSelected(_ color: NSColor) {
        canvasView.currentColor = color
    }

    // Optional: Clear button or menu action
    @IBAction func clearCanvas(_ sender: Any) {
        canvasView.clearCanvas()
    }
}

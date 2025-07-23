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
        
        colorSwatchView.color = canvasView.currentColor
        //self?.presentColorSelection(currentColor: self!.colorSwatchView.color)
        colorSwatchView.onClick = { [weak self] in
            self?.presentColorSelection()
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
           guard let self = self else { return event }
           return self.handleGlobalKeyDown(event)
       }
    }
    
    var colorPickerWindow: ColorSelectionWindowController?

    func presentColorSelection() {
        print("presentColorSelection")
        let initialRGB: [Double]
        
        if canvasView.colorFromSelectionWindow {
            initialRGB = AppColorState.shared.rgb
            print("Stored RGB")
        } else {
            guard let rgbColor = canvasView.currentColor.usingColorSpace(.deviceRGB) else {
                print("Failed to convert color to deviceRGB")
                return
            }
            initialRGB = [
                Double(rgbColor.redComponent * 255.0),
                Double(rgbColor.greenComponent * 255.0),
                Double(rgbColor.blueComponent * 255.0)
            ]
            print("RGB from canvas")
        }

        let colorWindow = ColorSelectionWindowController(initialRGB: initialRGB) { newColor in
            NotificationCenter.default.post(name: .colorPicked, object: newColor)
        }

        colorWindow.showWindow(nil)
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
        canvasView.colorFromSelectionWindow = false
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
            print("Failed to convert color to deviceRGB")
            return
        }
        AppColorState.shared.rgb = [
            Double(rgbColor.redComponent * 255.0),
            Double(rgbColor.greenComponent * 255.0),
            Double(rgbColor.blueComponent * 255.0)
        ]
        colorSwatchView.color = rgbColor
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

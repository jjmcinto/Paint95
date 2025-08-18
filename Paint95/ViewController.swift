// ViewController.swift
import Cocoa  // ✅ Import AppKit for NSViewController, NSColor, etc.

class ViewController: NSViewController, ToolbarDelegate, ColourPaletteDelegate, CanvasViewDelegate, ToolSizeSelectorDelegate {

    @IBOutlet weak var canvasView: CanvasView!
    @IBOutlet weak var toolbarView: ToolbarView!
    @IBOutlet weak var colourPaletteView: ColourPaletteView!
    @IBOutlet weak var colourSwatchView: ColourSwatchView!
    
    var toolSizeButtons: [NSButton] = []
    var colourPickerWindow: ColourSelectionWindowController?
    private var colourWindowController: ColourSelectionWindowController?
    
    deinit {
        print("ViewController deinitialized")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(updateColourSwatch(_:)), name: .colourPicked, object: nil)
        
        toolbarView.delegate = self
        colourPaletteView.delegate = self
        canvasView.delegate = self
        
        // Assuming ToolSizeSelectorView is a subview in your ViewController
        let toolSizeSelectorView = ToolSizeSelectorView(frame: CGRect(x: 448, y: 4, width: 452, height: 50))
        toolSizeSelectorView.delegate = self  // Set the delegate to self (ViewController)
        self.view.addSubview(toolSizeSelectorView)
        
        colourSwatchView.colour = canvasView.currentColour
        colourSwatchView.onClick = { [weak self] in
            self?.presentColourSelection()
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
           guard let self = self else { return event }
           return self.handleGlobalKeyDown(event)
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }

    
    func presentColourSelection() {
        let initialRGB: [Double]
        
        if canvasView.colourFromSelectionWindow {
            initialRGB = AppColourState.shared.rgb
        } else {
            guard let rgbColour = canvasView.currentColour.usingColorSpace(.deviceRGB) else {
                print("Failed to convert colour to deviceRGB")
                return
            }
            initialRGB = [
                Double(rgbColour.redComponent * 255.0),
                Double(rgbColour.greenComponent * 255.0),
                Double(rgbColour.blueComponent * 255.0)
            ]
        }

        let controller = ColourSelectionWindowController(
                    initialRGB: initialRGB,
                    onColourSelected: { [weak self] newColour in
                        // Broadcast and clean up
                        NotificationCenter.default.post(name: .colourPicked, object: newColour)
                        self?.colourWindowController = nil
                    },
                    onCancel: { [weak self] in
                        // Just release when the user cancels/closes
                        self?.colourWindowController = nil
                    }
                )

        colourWindowController = controller
                controller.showWindow(self.view.window)          // present
                controller.window?.makeKeyAndOrderFront(nil)     // ensure frontmost
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

    @objc func updateColourSwatch(_ notification: Notification) {
        if let colour = notification.object as? NSColor {
            colourSwatchView.colour = colour
        }
    }

    // MARK: - ToolbarDelegate
    func toolSelected(_ tool: PaintTool) {
        canvasView.currentTool = tool
    }
    
    func toolSizeSelected(_ size: CGFloat) {
        canvasView.toolSize = size
    }
    
    // MARK: - ColourPaletteDelegate
    func colourSelected(_ colour: NSColor) {
        canvasView.currentColour = colour
        canvasView.colourFromSelectionWindow = false
        guard let rgbColour = colour.usingColorSpace(.deviceRGB) else {
            print("Failed to convert colour to deviceRGB")
            return
        }
        AppColourState.shared.rgb = [
            Double(rgbColour.redComponent * 255.0),
            Double(rgbColour.greenComponent * 255.0),
            Double(rgbColour.blueComponent * 255.0)
        ]
        colourSwatchView.colour = rgbColour
    }
    
    // Optional: Clear button or menu action
    @IBAction func clearCanvas(_ sender: Any) {
        canvasView.clearCanvas()
    }
    func didPickColour(_ colour: NSColor) {
        canvasView.currentColour = colour
        colourPaletteView.selectedColour = colour
        colourPaletteView.needsDisplay = true
        colourSwatchView.colour = colour
    }
}

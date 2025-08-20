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
        
        // --- Create tool-size selector ---
        let toolSizeSelectorView = ToolSizeSelectorView()
        toolSizeSelectorView.translatesAutoresizingMaskIntoConstraints = false
        toolSizeSelectorView.delegate = self
        
        // --- Bottom row (palette + tool-size) ---
        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fill
        bottomRow.spacing = 12
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(bottomRow)
        
        // Reparent the palette into the bottom row so storyboard constraints won’t fight us
        colourPaletteView.removeFromSuperview()
        colourPaletteView.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.addArrangedSubview(colourPaletteView)
        NSLayoutConstraint.activate([
            colourPaletteView.heightAnchor.constraint(equalToConstant: 80),
            colourPaletteView.widthAnchor.constraint(equalToConstant: 320)
        ])
        
        // Add the tool-size selector to the bottom row (to the right of the palette)
        bottomRow.addArrangedSubview(toolSizeSelectorView)
        NSLayoutConstraint.activate([
            toolSizeSelectorView.heightAnchor.constraint(equalToConstant: 36)
        ])
        toolSizeSelectorView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolSizeSelectorView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        colourPaletteView.setContentHuggingPriority(.required, for: .horizontal)
        
        // Position the entire bottom row: to the right of the toolbar, along the bottom, full width
        NSLayoutConstraint.activate([
            bottomRow.leadingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: 8),
            bottomRow.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12),
            bottomRow.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -8)
        ])
        
        colourSwatchView.colour = canvasView.currentColour
        colourSwatchView.onClick = { [weak self] in
            self?.presentColourSelection()
        }
        
        // --- Enable scrolling for the existing canvasView ---
        if let host = canvasView.superview {
            let oldCanvas = canvasView!
            oldCanvas.removeFromSuperview()
            
            let scroll = NSScrollView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = false
            scroll.borderType = .bezelBorder
            scroll.drawsBackground = true
            scroll.backgroundColor = .windowBackgroundColor
            
            host.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: 8),
                scroll.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 8),
                scroll.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -8),
                scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: 0)
            ])
            
            oldCanvas.translatesAutoresizingMaskIntoConstraints = true
            scroll.documentView = oldCanvas
            oldCanvas.updateCanvasSize(to: oldCanvas.canvasRect.size)
        }
        
        // Global key handling
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

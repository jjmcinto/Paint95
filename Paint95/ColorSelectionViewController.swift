//ColorSelectionViewController.swift
import AppKit

class ColorSelectionViewController: NSViewController {

    var onColorSelected: ((NSColor) -> Void)?
    var rgb: [Double] = [0, 0, 0]

    private var redField = NSTextField()
    private var greenField = NSTextField()
    private var blueField = NSTextField()
    private var colorPreview = NSView()
    
    init(rgb: [Double], onColorSelected: @escaping (NSColor) -> Void) {
        self.rgb = rgb
        self.onColorSelected = onColorSelected
        super.init(nibName: nil, bundle: nil)
    }
    /*
    init(initialColor: NSColor, onColorSelected: @escaping (NSColor) -> Void) {
        self.initialColor = initialColor
        self.onColorSelected = onColorSelected
        redField.doubleValue = SharedColor.rgb[0]
        greenField.doubleValue = SharedColor.rgb[1]
        blueField.doubleValue = SharedColor.rgb[2]
        super.init(nibName: nil, bundle: nil)
        updatePreviewColor()
    }
    */

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        self.view = view
        buildUI()
    }
    
    func buildUI() {
        let labels = ["Red:", "Green:", "Blue:"]
        let yPositions: [CGFloat] = [140, 100, 60]

        for (i, labelText) in labels.enumerated() {
            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 20, y: yPositions[i], width: 50, height: 24)
            view.addSubview(label)

            let field = NSTextField(frame: NSRect(x: 80, y: yPositions[i], width: 60, height: 24))
            NotificationCenter.default.addObserver(self,
                selector: #selector(colorChanged),
                name: NSControl.textDidChangeNotification,
                object: field)
            view.addSubview(field)

            switch i {
            case 0: redField = field
            case 1: greenField = field
            case 2: blueField = field
            default: break
            }
        }

        colorPreview = NSView(frame: NSRect(x: 160, y: 60, width: 100, height: 60))
        colorPreview.wantsLayer = true
        colorPreview.layer?.borderColor = NSColor.black.cgColor
        colorPreview.layer?.borderWidth = 1
        view.addSubview(colorPreview)

        let okButton = NSButton(title: "OK", target: self, action: #selector(okPressed))
        okButton.frame = NSRect(x: 160, y: 20, width: 50, height: 24)
        view.addSubview(okButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancelButton.frame = NSRect(x: 220, y: 20, width: 60, height: 24)
        view.addSubview(cancelButton)

        redField.doubleValue = rgb[0]
        greenField.doubleValue = rgb[1]
        blueField.doubleValue = rgb[2]
        updatePreviewColor()
        
        applyInitialColor()
    }

    private func applyInitialColor() {
        redField.doubleValue = self.rgb[0]
        greenField.doubleValue = self.rgb[1]
        blueField.doubleValue = self.rgb[2]
        updatePreviewColor()
    }

    @objc private func colorChanged() {
        updatePreviewColor()
    }

    private func updatePreviewColor() {
        let r = CGFloat(redField.doubleValue / 255.0)
        let g = CGFloat(greenField.doubleValue / 255.0)
        let b = CGFloat(blueField.doubleValue / 255.0)
        let color = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        colorPreview.layer?.backgroundColor = color.cgColor
    }

    @objc func okPressed() {
        let r = redField.doubleValue
        let g = greenField.doubleValue
        let b = blueField.doubleValue

        let color = NSColor(calibratedRed: CGFloat(r / 255.0), green: CGFloat(g / 255.0), blue: CGFloat(b / 255.0), alpha: 1.0)

        // Save to RGB list for next time
        AppColorState.shared.rgb = [Double(redField.doubleValue), Double(greenField.doubleValue), Double(blueField.doubleValue)]

        // Post notification
        NotificationCenter.default.post(name: .colorPicked, object: color)

        onColorSelected?(color)
        view.window?.close()
    }

    @objc private func cancelPressed() {
        view.window?.close()
    }
}

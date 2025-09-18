// ColourSelectionViewController.swift
/*
import AppKit

final class ColorSelectionViewController: NSViewController, NSTextFieldDelegate {

    // MARK: - Public API (constructor callback)
    private let onPick: (NSColor) -> Void
    private let onCancel: () -> Void

    // MARK: - UI
    private let preview = NSView()
    private let rField = NSTextField()
    private let gField = NSTextField()
    private let bField = NSTextField()
    private let eyedropperButton = NSButton(title: "Eyedropper…", target: nil, action: nil)
    private let okButton = NSButton(title: "OK", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let swatchGrid = NSGridView()

    // MARK: - State
    private var selectedColor: NSColor {
        didSet { refreshPreviewAndFields(from: selectedColor) }
    }

    // MARK: - Init
    init(rgb: [Double], onPick: @escaping (NSColor) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel

        // Build starting color from provided RGB (0–255)
        let r = CGFloat((rgb.count > 0 ? rgb[0] : 0) / 255.0)
        let g = CGFloat((rgb.count > 1 ? rgb[1] : 0) / 255.0)
        let b = CGFloat((rgb.count > 2 ? rgb[2] : 0) / 255.0)
        self.selectedColor = NSColor(deviceRed: r, green: g, blue: b, alpha: 1.0)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - View lifecycle
    override func loadView() {
        self.view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        buildUI()
        layoutUI()
        refreshPreviewAndFields(from: selectedColor)
    }

    // MARK: - UI builders

    private func buildUI() {
        // Preview
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor.separatorColor.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)

        // Labels + fields
        let rLabel = label("R:")
        let gLabel = label("G:")
        let bLabel = label("B:")

        [rField, gField, bField].forEach { tf in
            tf.alignment = .right
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.bezelStyle = .roundedBezel
            tf.isBordered = true
            tf.drawsBackground = true
            tf.delegate = self
            tf.target = self
            tf.action = #selector(rgbFieldCommitted(_:))
            tf.formatter = integer0_255Formatter()
            tf.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            tf.controlSize = .small
            view.addSubview(tf)
        }

        // Eyedropper opens the native color panel; we listen for changes
        eyedropperButton.target = self
        eyedropperButton.action = #selector(openColorPanel)
        eyedropperButton.bezelStyle = .rounded
        eyedropperButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eyedropperButton)

        // OK / Cancel
        okButton.target = self
        okButton.action = #selector(confirmColor)
        okButton.keyEquivalent = "\r"
        okButton.bezelStyle = .rounded
        okButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.target = self
        cancelButton.action = #selector(cancelDialog)
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(okButton)
        view.addSubview(cancelButton)

        // Swatch grid (rainbow-like palette)
        swatchGrid.translatesAutoresizingMaskIntoConstraints = false
        buildSwatchGrid()
        view.addSubview(swatchGrid)

        // Put labels *after* to be on view
        view.addSubview(rLabel)
        view.addSubview(gLabel)
        view.addSubview(bLabel)

        // Constraints for labels relative to fields (we need references)
        NSLayoutConstraint.activate([
            rLabel.leadingAnchor.constraint(equalTo: rField.leadingAnchor, constant: -22),
            rLabel.centerYAnchor.constraint(equalTo: rField.centerYAnchor),
            gLabel.leadingAnchor.constraint(equalTo: gField.leadingAnchor, constant: -22),
            gLabel.centerYAnchor.constraint(equalTo: gField.centerYAnchor),
            bLabel.leadingAnchor.constraint(equalTo: bField.leadingAnchor, constant: -22),
            bLabel.centerYAnchor.constraint(equalTo: bField.centerYAnchor),
        ])
    }

    private func layoutUI() {
        // Layout constants
        let margin: CGFloat = 16

        NSLayoutConstraint.activate([
            // Preview (top-left)
            preview.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            preview.widthAnchor.constraint(equalToConstant: 64),
            preview.heightAnchor.constraint(equalToConstant: 64),

            // Eyedropper to the right of preview
            eyedropperButton.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            eyedropperButton.centerYAnchor.constraint(equalTo: preview.centerYAnchor),

            // RGB fields under preview/eyedropper
            rField.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
            rField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 22),
            rField.widthAnchor.constraint(equalToConstant: 60),

            gField.topAnchor.constraint(equalTo: rField.bottomAnchor, constant: 6),
            gField.leadingAnchor.constraint(equalTo: rField.leadingAnchor),
            gField.widthAnchor.constraint(equalTo: rField.widthAnchor),

            bField.topAnchor.constraint(equalTo: gField.bottomAnchor, constant: 6),
            bField.leadingAnchor.constraint(equalTo: rField.leadingAnchor),
            bField.widthAnchor.constraint(equalTo: rField.widthAnchor),

            // Swatch grid to the right, fills horizontally
            swatchGrid.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            swatchGrid.leadingAnchor.constraint(equalTo: eyedropperButton.trailingAnchor, constant: 16),
            swatchGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),

            // Swatch grid height
            swatchGrid.heightAnchor.constraint(equalToConstant: 220),

            // OK / Cancel at bottom-right
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),

            okButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            okButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func integer0_255Formatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 255
        f.allowsFloats = false
        return f
    }

    // MARK: - Swatches

    private func buildSwatchGrid() {
        // A rainbow-like palette: rows of hues + grayscale.
        // Each item is a button that sets selectedColor.
        let rows: [[NSColor]] = makeRainbowPalette()

        var rowViews: [[NSView]] = []
        for row in rows {
            var cells: [NSView] = []
            for color in row {
                let b = ColorSwatchButton.make(swatchColor: color, target: self, action: #selector(swatchTapped(_:)))
                cells.append(b)
            }
            rowViews.append(cells)
        }

        for row in rowViews {
            swatchGrid.addRow(with: row)
        }

        swatchGrid.rowSpacing = 6
        swatchGrid.columnSpacing = 6
        swatchGrid.yPlacement = .top
        swatchGrid.xPlacement = .leading
    }

    private func makeRainbowPalette() -> [[NSColor]] {
        // 8 rows: 6 rainbow rows with varying brightness + a grayscale row + a common-colors row.
        func colors(hues: Int, sat: CGFloat, bri: CGFloat) -> [NSColor] {
            (0..<hues).map { i in
                let h = CGFloat(i) / CGFloat(hues)
                return NSColor(calibratedHue: h, saturation: sat, brightness: bri, alpha: 1.0)
            }
        }

        let row1 = colors(hues: 12, sat: 1.0, bri: 1.0)
        let row2 = colors(hues: 12, sat: 0.9, bri: 1.0)
        let row3 = colors(hues: 12, sat: 0.75, bri: 1.0)
        let row4 = colors(hues: 12, sat: 0.6, bri: 1.0)
        let row5 = colors(hues: 12, sat: 0.45, bri: 1.0)
        let row6 = colors(hues: 12, sat: 0.3, bri: 1.0)

        // Grayscale
        let grayRow: [NSColor] = (0...11).map { i in
            let v = CGFloat(i) / 11.0
            return NSColor(white: v, alpha: 1.0)
        }

        // Common quick picks
        let common: [NSColor] = [
            .black, .darkGray, .gray, .lightGray, .white,
            .red, .orange, .yellow, .green, .blue, .systemBlue, .purple
        ]

        return [row1, row2, row3, row4, row5, row6, grayRow, common]
    }

    // MARK: - Actions

    @objc private func swatchTapped(_ sender: NSButton) {
        guard let b = sender as? ColorSwatchButton else { return }
        selectedColor = b.swatchColor
    }

    @objc private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = selectedColor
        panel.makeKeyAndOrderFront(self)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        selectedColor = panel.color.usingColorSpace(.deviceRGB) ?? panel.color
    }

    @objc private func confirmColor() {
        onPick(selectedColor)
    }

    @objc private func cancelDialog() {
        onCancel()
    }

    // Called when user presses Return in a field or ends editing.
    @objc private func rgbFieldCommitted(_ sender: Any?) {
        // Clamp 0..255 then update color
        let r = clampTo255(rField.integerValue)
        let g = clampTo255(gField.integerValue)
        let b = clampTo255(bField.integerValue)
        selectedColor = NSColor(deviceRed: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        rgbFieldCommitted(nil)
    }

    private func clampTo255(_ v: Int) -> Int {
        return max(0, min(255, v))
    }

    private func refreshPreviewAndFields(from color: NSColor) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        preview.layer?.backgroundColor = rgb.cgColor

        // Avoid feedback loops: set without firing actions
        rField.target = nil; gField.target = nil; bField.target = nil
        rField.stringValue = String(Int(round(rgb.redComponent * 255)))
        gField.stringValue = String(Int(round(rgb.greenComponent * 255)))
        bField.stringValue = String(Int(round(rgb.blueComponent * 255)))
        rField.target = self; gField.target = self; bField.target = self
    }
}
*/

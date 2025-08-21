// ColourSelectionWindowController.swift
import AppKit

final class ColourSelectionWindowController: NSWindowController, NSWindowDelegate, ColourPaletteDelegate, NSTextFieldDelegate {

    private let onColourSelected: (NSColor) -> Void
    private let onCancel: () -> Void

    // UI
    private let colourMapView = ColourMapView()
    private let rField = NSTextField()
    private let gField = NSTextField()
    private let bField = NSTextField()
    private let hexField = NSTextField()
    private let okButton = NSButton(title: "OK", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let preview = NSView()

    // State
    private var initialR: Int
    private var initialG: Int
    private var initialB: Int

    private var currentColour: NSColor {
        didSet { updatePreview() }
    }

    // MARK: - Init
    init(initialRGB: [Double],
         onColourSelected: @escaping (NSColor) -> Void,
         onCancel: @escaping () -> Void = { }) {

        self.onColourSelected = onColourSelected
        self.onCancel = onCancel

        let r = Int(initialRGB[safe: 0] ?? 0)
        let g = Int(initialRGB[safe: 1] ?? 0)
        let b = Int(initialRGB[safe: 2] ?? 0)
        self.initialR = r
        self.initialG = g
        self.initialB = b

        self.currentColour = NSColor(deviceRed: CGFloat(max(0, min(255, r)))/255.0,
                                     green: CGFloat(max(0, min(255, g)))/255.0,
                                     blue: CGFloat(max(0, min(255, b)))/255.0,
                                     alpha: 1.0)

        let contentSize = NSSize(width: 520, height: 420)
        let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: contentSize.width, height: contentSize.height),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Select Colour"
        window.isMovableByWindowBackground = true
        window.center()

        super.init(window: window)
        window.delegate = self

        // Build UI immediately:
        setupUI()

        // Apply initial colour AFTER UI exists
        applyInitialRGB(r: r, g: g, b: b)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func windowDidLoad() {
        super.windowDidLoad()
        setupUI()
        applyInitialRGB(r: initialR, g: initialG, b: initialB)
    }

    // MARK: - Build UI
    private func setupUI() {
        guard let content = window?.contentView else { return }

        // --- LEFT: colour map ----------------------------------------------------
        colourMapView.translatesAutoresizingMaskIntoConstraints = false
        colourMapView.delegate = self            // uses ColourPaletteDelegate now
        colourMapView.wantsLayer = true
        colourMapView.layer?.cornerRadius = 6
        colourMapView.layer?.masksToBounds = true
        colourMapView.layer?.borderColor = NSColor.separatorColor.cgColor
        colourMapView.layer?.borderWidth = 1
        content.addSubview(colourMapView)

        // --- RIGHT: controls container ------------------------------------------
        let right = NSView()
        right.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(right)

        // Preview swatch
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.borderColor = NSColor.separatorColor.cgColor
        preview.layer?.borderWidth = 1
        right.addSubview(preview)

        // RGB fields
        [rField, gField, bField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.alignment = .right
            $0.placeholderString = "0–255"
            $0.delegate = self
            $0.formatter = integer255Formatter()
            right.addSubview($0)
        }

        // Hex field
        hexField.translatesAutoresizingMaskIntoConstraints = false
        hexField.placeholderString = "#RRGGBB"
        hexField.delegate = self
        right.addSubview(hexField)

        // Buttons
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.target = self
        okButton.action = #selector(tapOK)
        right.addSubview(okButton)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(tapCancel)
        right.addSubview(cancelButton)

        // --- CONSTRAINTS ---------------------------------------------------------
        let mapWidth = ColourMapProvider.mapSize.width > 0 ? ColourMapProvider.mapSize.width : 256

        NSLayoutConstraint.activate([
            // Left/map
            colourMapView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            colourMapView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            colourMapView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            colourMapView.widthAnchor.constraint(equalToConstant: mapWidth),

            // Right column
            right.leadingAnchor.constraint(equalTo: colourMapView.trailingAnchor, constant: 16),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            right.topAnchor.constraint(equalTo: colourMapView.topAnchor),
            right.bottomAnchor.constraint(equalTo: colourMapView.bottomAnchor),

            // Preview at top
            preview.topAnchor.constraint(equalTo: right.topAnchor),
            preview.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            preview.heightAnchor.constraint(equalToConstant: 80),

            // RGB row
            rField.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 16),
            rField.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            rField.widthAnchor.constraint(equalToConstant: 80),

            gField.leadingAnchor.constraint(equalTo: rField.trailingAnchor, constant: 12),
            gField.centerYAnchor.constraint(equalTo: rField.centerYAnchor),
            gField.widthAnchor.constraint(equalTo: rField.widthAnchor),

            bField.leadingAnchor.constraint(equalTo: gField.trailingAnchor, constant: 12),
            bField.centerYAnchor.constraint(equalTo: rField.centerYAnchor),
            bField.widthAnchor.constraint(equalTo: rField.widthAnchor),
            bField.trailingAnchor.constraint(lessThanOrEqualTo: right.trailingAnchor),

            // Hex field
            hexField.topAnchor.constraint(equalTo: rField.bottomAnchor, constant: 12),
            hexField.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            hexField.trailingAnchor.constraint(equalTo: right.trailingAnchor),

            // Buttons aligned at bottom-right
            okButton.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            okButton.bottomAnchor.constraint(equalTo: right.bottomAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor)
        ])

        colourMapView.setContentHuggingPriority(.required, for: .horizontal)
        colourMapView.setContentCompressionResistancePriority(.required, for: .horizontal)

        updatePreview()
        updateHexFromRGB()
    }

    // MARK: - Actions
    @objc private func tapOK() {
        let r = max(0, min(255, Int(rField.stringValue) ?? 0))
        let g = max(0, min(255, Int(gField.stringValue) ?? 0))
        let b = max(0, min(255, Int(bField.stringValue) ?? 0))

        if let c = colourFromFields() {
            onColourSelected(c)
        } else {
            onColourSelected(currentColour)
        }
        NotificationCenter.default.post(
            name: .colourCommitted,
            object: nil,
            userInfo: ["r": r, "g": g, "b": b]
        )
        initialR = r
        initialG = g
        initialB = b
        AppColourState.shared.rgb = [Double(r), Double(g), Double(b)]
        close()
    }

    @objc private func tapCancel() {
        onCancel()
        close()
    }

    // MARK: - ColourPaletteDelegate (used by ColourMapView)
    func colourSelected(_ colour: NSColor) {
        let dev = colour.usingColorSpace(.deviceRGB) ?? colour
        let r = Int(round(dev.redComponent * 255))
        let g = Int(round(dev.greenComponent * 255))
        let b = Int(round(dev.blueComponent * 255))
        applyInitialRGB(r: r, g: g, b: b)
    }

    // MARK: - Fields <-> Colour
    private func integer255Formatter() -> NumberFormatter {
        let nf = NumberFormatter()
        nf.minimum = 0
        nf.maximum = 255
        nf.allowsFloats = false
        return nf
    }

    private func applyInitialRGB(r: Int, g: Int, b: Int) {
        rField.stringValue = "\(clamp255(r))"
        gField.stringValue = "\(clamp255(g))"
        bField.stringValue = "\(clamp255(b))"
        currentColour = NSColor(deviceRed: CGFloat(clamp255(r))/255.0,
                                green: CGFloat(clamp255(g))/255.0,
                                blue: CGFloat(clamp255(b))/255.0,
                                alpha: 1.0)
        updateHexFromRGB()
    }

    private func colourFromFields() -> NSColor? {
        guard let r = Int(rField.stringValue),
              let g = Int(gField.stringValue),
              let b = Int(bField.stringValue) else { return nil }
        let rr = clamp255(r), gg = clamp255(g), bb = clamp255(b)
        return NSColor(deviceRed: CGFloat(rr)/255.0,
                       green: CGFloat(gg)/255.0,
                       blue: CGFloat(bb)/255.0,
                       alpha: 1.0)
    }

    private func updatePreview() {
        preview.layer?.backgroundColor = currentColour.cgColor
    }

    private func updateHexFromRGB() {
        guard let c = colourFromFields() else { return }
        let dev = c.usingColorSpace(.deviceRGB) ?? c
        let r = Int(round(dev.redComponent * 255))
        let g = Int(round(dev.greenComponent * 255))
        let b = Int(round(dev.blueComponent * 255))
        hexField.stringValue = String(format: "#%02X%02X%02X", r, g, b)
    }

    private func updateRGBFromHex() {
        let s = hexField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard cleaned.count == 6, let v = Int(cleaned, radix: 16) else { return }
        let r = (v >> 16) & 0xFF
        let g = (v >> 8) & 0xFF
        let b = v & 0xFF
        applyInitialRGB(r: r, g: g, b: b)
    }

    // MARK: - NSTextFieldDelegate
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field == hexField {
            updateRGBFromHex()
        } else {
            if let c = colourFromFields() { currentColour = c }
            updateHexFromRGB()
        }
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        onCancel()
    }

    // MARK: - Helpers
    private func clamp255(_ x: Int) -> Int { max(0, min(255, x)) }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        (0..<count).contains(index) ? self[index] : nil
    }
}

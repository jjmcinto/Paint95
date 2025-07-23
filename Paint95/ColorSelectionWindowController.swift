// ColorSelectionWindowController.swift
import AppKit

class ColorSelectionWindowController: NSWindowController {

    var onColorSelected: ((NSColor) -> Void)?
    var initialRGB: [Double]

    init(initialRGB: [Double], onColorSelected: @escaping (NSColor) -> Void) {
        self.initialRGB = initialRGB
        self.onColorSelected = onColorSelected

        let contentSize = NSSize(width: 300, height: 250)
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: contentSize.width, height: contentSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Select Color"
        
        super.init(window: window)

        let viewController = ColorSelectionViewController(rgb: initialRGB) { selectedColor in
            onColorSelected(selectedColor)
            self.close()
        }

        self.contentViewController = viewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

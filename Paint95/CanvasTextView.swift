import Cocoa

class CanvasTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 // Return key
        let isShiftHeld = event.modifierFlags.contains(.shift)

        if isReturn {
            if isShiftHeld {
                // Insert newline
                self.insertNewline(nil)
            } else {
                // Commit text (trigger loss of focus)
                self.window?.makeFirstResponder(nil)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

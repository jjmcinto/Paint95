// UndoManager.swift
import Cocoa

class PaintUndoManager {
    private var undoStack: [NSImage] = []
    private var redoStack: [NSImage] = []

    func saveState(_ image: NSImage) {
        undoStack.append(image.copy() as! NSImage)
        redoStack.removeAll()
    }

    func undo(current: NSImage) -> NSImage? {
        guard let last = undoStack.popLast() else { return nil }
        redoStack.append(current.copy() as! NSImage)
        return last
    }

    func redo(current: NSImage) -> NSImage? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current.copy() as! NSImage)
        return next
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

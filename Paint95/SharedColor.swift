// SharedColor.swift
import AppKit

enum ColorSource {
    case palette
    case colorSelection
}

struct SharedColor {
    static var rgb: [Double] = [0, 0, 0] // always stores exact values from Color Selection Window
    static var currentColor: NSColor = .black
    static var source: ColorSource = .palette
}

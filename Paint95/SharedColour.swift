// SharedColour.swift
import AppKit

enum ColourSource {
    case palette
    case colourSelection
}

struct SharedColour {
    static var rgb: [Double] = [0, 0, 0] // always stores exact values from Colour Selection Window
    static var currentColour: NSColor = .black
    static var source: ColourSource = .palette
}

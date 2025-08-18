// ColourPalette.swift
import AppKit

enum ColourPalette {
    private static let key = "Paint95.ColourRecents.v1"

    static func loadRecents() -> [NSColor] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let colours = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: NSColor.self, from: data)
        else {
            return []
        }
        return colours
    }

    static func saveRecents(_ colours: [NSColor]) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: colours, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

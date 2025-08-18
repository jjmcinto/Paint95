// ColorPalette.swift
import AppKit

enum ColorPalette {
    private static let key = "Paint95.ColorRecents.v1"

    static func loadRecents() -> [NSColor] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let colors = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: NSColor.self, from: data)
        else {
            return []
        }
        return colors
    }

    static func saveRecents(_ colors: [NSColor]) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: colors, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/*
import AppKit

enum AppPalette {
    // A “MS Paint-like” 28-color basic palette (feel free to tweak)
    static let basicHex: [UInt32] = [
        0x000000, 0x808080, 0xC0C0C0, 0xFFFFFF, 0x800000, 0xFF0000, 0x808000,
        0xFFFF00, 0x008000, 0x00FF00, 0x008080, 0x00FFFF, 0x000080, 0x0000FF,
        0x800080, 0xFF00FF, 0x804000, 0xFF8000, 0x408000, 0x80FF00, 0x008040,
        0x00FF80, 0x004080, 0x0080FF, 0x400080, 0x8000FF, 0x808000, 0xFF8080
    ]

    static func color(from hex: UInt32) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    static var basic: [NSColor] {
        basicHex.map { color(from: $0) }
    }

    // Persisted recents
    private static let recentsKey = "AppPaletteRecentColors"
    static let maxRecents = 12

    static func loadRecents() -> [NSColor] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "recentColors") {
            do {
                if let colors = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSColor.self], from: data) as? [NSColor] {
                    return colors
                }
            } catch {
                print("Failed to unarchive recent colors:", error)
            }
        }
        return []
    }

    static func saveRecents(_ colors: [NSColor]) {
        let defaults = UserDefaults.standard
        do {
            // NSColor supports NSSecureCoding
            let data = try NSKeyedArchiver.archivedData(withRootObject: colors, requiringSecureCoding: true)
            defaults.set(data, forKey: "recentColors")
        } catch {
            print("Failed to archive recent colors (secure):", error)
            // Fallback (non-secure) to avoid losing data if something odd happens
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: colors, requiringSecureCoding: false) {
                defaults.set(data, forKey: "recentColors")
            }
        }
    }

    static func pushRecent(_ color: NSColor) {
        var curr = loadRecents()
        // Dedup (same RGB within tolerance)
        curr.removeAll { $0.usingColorSpace(.deviceRGB) == color.usingColorSpace(.deviceRGB) }
        curr.insert(color, at: 0)
        if curr.count > maxRecents { curr.removeLast(curr.count - maxRecents) }
        saveRecents(curr)
    }
}
*/

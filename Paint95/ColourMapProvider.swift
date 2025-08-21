// ColourMapProvider.swift
import AppKit

enum ColourMapProvider {
    static let mapSize = NSSize(width: 360, height: 240) // width sweeps hue, height mixes sat/brightness
    static let fileName = "colourmap.png"
    private static let hueStops: [(CGFloat, NSColor)] = [
        (0.0,   NSColor.red),
        (0.08,  NSColor.orange), // give orange explicit space
        (0.17,  NSColor.yellow),
        (0.33,  NSColor.green),
        (0.5,   NSColor.cyan),
        (0.67,  NSColor.blue),
        (0.83,  NSColor.magenta),
        (1.0,   NSColor.red)
    ]

    private static var colourMapURL: URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "Paint95"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    static func ensureColourMapImage() -> URL? {
        let url = colourMapURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let image = makeColourMapImage(size: mapSize) else { return nil }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func makeColourMapImage(size: NSSize) -> NSImage? {
        // Strategy:
        //  - X axis (0 → width): Hue 0..360
        //  - Y axis (top → bottom): mix Saturation/Brightness in a simple 2D ramp:
        //      top row: V=1.0, S from 0→1
        //      bottom row: V from 1→0, S stays 1; then blend the two ramps across height.
        // This gives a rich “Paint-like” gamut with white top-left, fully vivid colours middle-top-right, darks at bottom.
        let w = Int(size.width)
        let h = Int(size.height)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: w,
                                         pixelsHigh: h,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }

        guard let data = rep.bitmapData else { return nil }

        for y in 0..<h {
            let yf = CGFloat(y) / CGFloat(h - 1) // 0 at top, 1 at bottom
            // Two ramps blended:
            // Ramp A (top): S goes 0→1, V = 1
            // Ramp B (bottom): S = 1, V goes 1→0
            // Blend factor t = yf
            for x in 0..<w {
                let xf = CGFloat(x) / CGFloat(w - 1)
                let hue = xf // 0..1
                let sTop = xf
                let vTop: CGFloat = 1.0
                let sBot: CGFloat = 1.0
                let vBot = 1.0 - yf

                let s = sTop * (1 - yf) + sBot * yf
                let v = vTop * (1 - yf) + vBot * yf

                let colour = NSColor(calibratedHue: hue, saturation: s, brightness: v, alpha: 1.0).usingColorSpace(.deviceRGB) ?? .black
                let r = UInt8(max(0, min(255, Int(round(colour.redComponent * 255)))))
                let g = UInt8(max(0, min(255, Int(round(colour.greenComponent * 255)))))
                let b = UInt8(max(0, min(255, Int(round(colour.blueComponent * 255)))))
                let offset = y * rep.bytesPerRow + x * rep.samplesPerPixel
                data[offset + 0] = r
                data[offset + 1] = g
                data[offset + 2] = b
                data[offset + 3] = 255
            }
        }

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    static func loadImage() -> NSImage? {
        let size = mapSize
        let image = NSImage(size: size)
        image.lockFocus()

        // Horizontal hue gradient with bias for orange
        let gradient = NSGradient(colorsAndLocations:
            (NSColor.red, 0.0),
            (NSColor.orange, 0.08),
            (NSColor.yellow, 0.17),
            (NSColor.green, 0.33),
            (NSColor.cyan, 0.5),
            (NSColor.blue, 0.67),
            (NSColor.magenta, 0.83),
            (NSColor.red, 1.0)
        )

        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 0)

        // Vertical fade to white at bottom
        let whiteGradient = NSGradient(colors: [NSColor.clear, NSColor.white])!
        whiteGradient.draw(in: NSRect(origin: .zero, size: size), angle: 90)

        image.unlockFocus()
        return image
    }

    static func colour(at point: NSPoint, in image: NSImage) -> NSColor? {
        // point is in image-pixel coordinates (0..w-1, 0..h-1)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }

        let x = Int(round(point.x))
        let y = Int(round(point.y))
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return nil }

        return rep.colorAt(x: x, y: y)
    }
}

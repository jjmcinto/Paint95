// ColorMapProvider.swift
import AppKit

enum ColorMapProvider {
    static let mapSize = NSSize(width: 360, height: 240) // width sweeps hue, height mixes sat/brightness
    static let fileName = "colormap.png"

    private static var colorMapURL: URL {
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

    static func ensureColorMapImage() -> URL? {
        let url = colorMapURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let image = makeColorMapImage(size: mapSize) else { return nil }
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

    private static func makeColorMapImage(size: NSSize) -> NSImage? {
        // Strategy:
        //  - X axis (0 → width): Hue 0..360
        //  - Y axis (top → bottom): mix Saturation/Brightness in a simple 2D ramp:
        //      top row: V=1.0, S from 0→1
        //      bottom row: V from 1→0, S stays 1; then blend the two ramps across height.
        // This gives a rich “Paint-like” gamut with white top-left, fully vivid colors middle-top-right, darks at bottom.
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

                let color = NSColor(calibratedHue: hue, saturation: s, brightness: v, alpha: 1.0).usingColorSpace(.deviceRGB) ?? .black
                let r = UInt8(max(0, min(255, Int(round(color.redComponent * 255)))))
                let g = UInt8(max(0, min(255, Int(round(color.greenComponent * 255)))))
                let b = UInt8(max(0, min(255, Int(round(color.blueComponent * 255)))))
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
        guard let url = ensureColorMapImage() else { return nil }
        return NSImage(contentsOf: url)
    }

    static func color(at point: NSPoint, in image: NSImage) -> NSColor? {
        // point is in image-pixel coordinates (0..w-1, 0..h-1)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }

        let x = Int(round(point.x))
        let y = Int(round(point.y))
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return nil }

        return rep.colorAt(x: x, y: y)
    }
}

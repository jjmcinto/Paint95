// ImageUtils.swift
import Cocoa

extension NSImage {
    /// Returns an RGBA8 bitmap representation of this image, or nil if it cannot be created.
    func rgba8Bitmap() -> NSBitmapImageRep? {
        guard let tiff = self.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }

        // Force RGBA8 (32 bits/pixel)
        if rep.bitsPerPixel == 32,
           rep.samplesPerPixel == 4,
           rep.bitmapFormat.contains(.alphaFirst) == false {
            return rep
        }

        // Re-render into RGBA8
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let cg = rep.cgImage {
            ctx.draw(cg, in: rect)
        }
        return NSBitmapImageRep(cgImage: ctx.makeImage()!)
    }
}

// ImageUtils.swift
import Cocoa
import UniformTypeIdentifiers

// MARK: - Image utilities

extension NSImage {
    /// Returns an RGBA8 bitmap representation of this image, or nil if it cannot be created.
    func rgba8Bitmap() -> NSBitmapImageRep? {
        guard let tiff = self.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }

        // Already RGBA8?
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
        guard let outCG = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: outCG)
    }
}

// MARK: - Legacy Paint formats

enum LegacyPaintFormat: CaseIterable {
    case bmp, gif, jpeg, png, tiff

    var displayName: String {
        switch self {
        case .bmp:  return "BMP (Bitmap)"
        case .gif:  return "GIF"
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .bmp:  return "bmp"
        case .gif:  return "gif"
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .tiff: return "tif"
        }
    }

    var fileType: NSBitmapImageRep.FileType {
        switch self {
        case .bmp:  return .bmp
        case .gif:  return .gif
        case .jpeg: return .jpeg
        case .png:  return .png
        case .tiff: return .tiff
        }
    }

    var utType: UTType {
        switch self {
        case .bmp:  return .bmp
        case .gif:  return .gif
        case .jpeg: return .jpeg
        case .png:  return .png
        case .tiff: return .tiff
        }
    }
}

// MARK: - Image export

struct ImageExporter {
    /// Returns encoded image data in the requested legacy format.
    /// - Parameters:
    ///   - image: The source NSImage (e.g., your canvas).
    ///   - format: Target format (BMP, GIF, JPEG, PNG, TIFF).
    ///   - jpegQuality: 0.0–1.0 (only used for JPEG).
    static func data(for image: NSImage,
                     as format: LegacyPaintFormat,
                     jpegQuality: CGFloat = 0.9) -> Data? {
        guard let rep = image.rgba8Bitmap() else { return nil }

        if format == .tiff {
            return rep.tiffRepresentation
        }

        var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if format == .jpeg {
            props[.compressionFactor] = max(0.0, min(1.0, jpegQuality))
        }
        return rep.representation(using: format.fileType, properties: props)
    }

    /// Convenience writer that wraps `data(for:as:)` and writes to disk.
    static func write(_ image: NSImage,
                      as format: LegacyPaintFormat,
                      to url: URL,
                      jpegQuality: CGFloat = 0.9) throws {
        guard let d = data(for: image, as: format, jpegQuality: jpegQuality) else {
            throw NSError(domain: "ImageExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image."])
        }
        try d.write(to: url, options: .atomic)
    }
}


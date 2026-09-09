import AppKit

@main
struct MakeIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 2,
              let symbol = NSImage(systemSymbolName: AppBrand.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 640, weight: .regular))?
                .withSymbolConfiguration(.init(paletteColors: [.white])) else {
            fatalError("Expected an iconset output directory and the app's system symbol.")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let side = CGFloat(pixels)
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = NSSize(width: side, height: side)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let tile = NSRect(x: side * 0.08, y: side * 0.08, width: side * 0.84, height: side * 0.84)
                NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
                NSBezierPath(roundedRect: tile, xRadius: side * 0.19, yRadius: side * 0.19).fill()
                let fit = min(side * 0.60 / symbol.size.width, side * 0.60 / symbol.size.height)
                let dimensions = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
                symbol.draw(in: NSRect(x: (side - dimensions.width) / 2, y: (side - dimensions.height) / 2,
                                      width: dimensions.width, height: dimensions.height))
                NSGraphicsContext.restoreGraphicsState()
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    fatalError("Could not encode app icon.")
                }
                let suffix = scale == 2 ? "@2x" : ""
                try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}

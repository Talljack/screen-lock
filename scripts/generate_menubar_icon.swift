#!/usr/bin/env swift

/// Generates menu bar icons by scaling down the full-color App icon.
/// No template conversion — retains the original pink gradient + bunny design.

import Cocoa

func savePNG(image: NSImage, size: Int, path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    let gfxCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gfxCtx
    gfxCtx.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("Generated: \(path) (\(size)x\(size))")
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sourceDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."

// Use the 256x256 icon for best quality scaling
guard let source = NSImage(contentsOfFile: "\(sourceDir)/icon_256x256.png") else {
    print("Error: Could not load \(sourceDir)/icon_256x256.png")
    exit(1)
}

// 18pt @1x and @2x for Retina
savePNG(image: source, size: 18, path: "\(outputDir)/menubar_icon_18x18.png")
savePNG(image: source, size: 36, path: "\(outputDir)/menubar_icon_18x18@2x.png")

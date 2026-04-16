#!/usr/bin/env swift

import Cocoa

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Background: rounded square with pink gradient
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 1.0, green: 0.72, blue: 0.82, alpha: 1.0),
        CGColor(red: 0.95, green: 0.58, blue: 0.72, alpha: 1.0),
        CGColor(red: 0.82, green: 0.45, blue: 0.68, alpha: 1.0),
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.5, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: s),
                              end: CGPoint(x: s, y: 0),
                              options: [])
    }

    // Small stars in background
    drawStar(ctx: ctx, cx: s * 0.15, cy: s * 0.82, radius: s * 0.025, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
    drawStar(ctx: ctx, cx: s * 0.85, cy: s * 0.78, radius: s * 0.02, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
    drawStar(ctx: ctx, cx: s * 0.72, cy: s * 0.88, radius: s * 0.018, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.4))
    drawStar(ctx: ctx, cx: s * 0.25, cy: s * 0.7, radius: s * 0.015, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
    drawStar(ctx: ctx, cx: s * 0.9, cy: s * 0.55, radius: s * 0.015, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))

    // Moon (crescent) via path subtraction
    let moonCx = s * 0.5
    let moonCy = s * 0.58
    let moonR = s * 0.25
    let cutR = moonR * 0.82
    let cutOffX = moonR * 0.5
    let cutOffY = moonR * 0.15

    // Moon glow (soft halo)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.1,
                  color: CGColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 0.5))

    let moonPath = CGMutablePath()
    moonPath.addEllipse(in: CGRect(x: moonCx - moonR, y: moonCy - moonR, width: moonR * 2, height: moonR * 2))

    let cutPath = CGMutablePath()
    cutPath.addEllipse(in: CGRect(x: moonCx + cutOffX - cutR, y: moonCy + cutOffY - cutR, width: cutR * 2, height: cutR * 2))

    // Use even-odd rule: the overlapping area is subtracted
    let crescentPath = CGMutablePath()
    crescentPath.addPath(moonPath)
    crescentPath.addPath(cutPath)

    ctx.setFillColor(CGColor(red: 1.0, green: 0.92, blue: 0.65, alpha: 1.0))
    ctx.addPath(crescentPath)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // Bunny sitting on the moon
    let bunnyX = moonCx - moonR * 0.15
    let bunnyY = moonCy - moonR * 0.6

    // Bunny body (white oval)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    let bodyW = s * 0.14
    let bodyH = s * 0.16
    ctx.addEllipse(in: CGRect(x: bunnyX - bodyW / 2, y: bunnyY - bodyH / 2, width: bodyW, height: bodyH))
    ctx.fillPath()

    // Bunny head (white circle)
    let headR = s * 0.065
    let headY = bunnyY + bodyH * 0.45
    ctx.addEllipse(in: CGRect(x: bunnyX - headR, y: headY - headR, width: headR * 2, height: headR * 2))
    ctx.fillPath()

    // Bunny ears (two elongated ovals)
    let earW = s * 0.028
    let earH = s * 0.09
    // Left ear
    ctx.saveGState()
    ctx.translateBy(x: bunnyX - s * 0.03, y: headY + headR + earH * 0.3)
    ctx.rotate(by: 0.15)
    ctx.addEllipse(in: CGRect(x: -earW / 2, y: 0, width: earW, height: earH))
    ctx.fillPath()
    // Inner ear (pink)
    ctx.setFillColor(CGColor(red: 1.0, green: 0.75, blue: 0.82, alpha: 0.9))
    let innerW = earW * 0.55
    let innerH = earH * 0.6
    ctx.addEllipse(in: CGRect(x: -innerW / 2, y: earH * 0.2, width: innerW, height: innerH))
    ctx.fillPath()
    ctx.restoreGState()

    // Right ear
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    ctx.saveGState()
    ctx.translateBy(x: bunnyX + s * 0.03, y: headY + headR + earH * 0.3)
    ctx.rotate(by: -0.15)
    ctx.addEllipse(in: CGRect(x: -earW / 2, y: 0, width: earW, height: earH))
    ctx.fillPath()
    ctx.setFillColor(CGColor(red: 1.0, green: 0.75, blue: 0.82, alpha: 0.9))
    ctx.addEllipse(in: CGRect(x: -innerW / 2, y: earH * 0.2, width: innerW, height: innerH))
    ctx.fillPath()
    ctx.restoreGState()

    // Bunny eyes (tiny black dots)
    let eyeR = s * 0.012
    let eyeSpacing = s * 0.025
    ctx.setFillColor(CGColor(red: 0.2, green: 0.15, blue: 0.2, alpha: 1.0))
    ctx.addEllipse(in: CGRect(x: bunnyX - eyeSpacing - eyeR, y: headY - eyeR * 0.5, width: eyeR * 2, height: eyeR * 2))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: bunnyX + eyeSpacing - eyeR, y: headY - eyeR * 0.5, width: eyeR * 2, height: eyeR * 2))
    ctx.fillPath()

    // Bunny nose (tiny pink dot)
    let noseR = s * 0.007
    ctx.setFillColor(CGColor(red: 1.0, green: 0.6, blue: 0.7, alpha: 1.0))
    ctx.addEllipse(in: CGRect(x: bunnyX - noseR, y: headY - s * 0.02, width: noseR * 2, height: noseR * 1.5))
    ctx.fillPath()

    // Bunny cheeks (pink blush)
    ctx.setFillColor(CGColor(red: 1.0, green: 0.7, blue: 0.78, alpha: 0.4))
    let blushR = s * 0.02
    ctx.addEllipse(in: CGRect(x: bunnyX - eyeSpacing * 1.6 - blushR, y: headY - blushR * 1.5, width: blushR * 2, height: blushR * 1.5))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: bunnyX + eyeSpacing * 1.6 - blushR, y: headY - blushR * 1.5, width: blushR * 2, height: blushR * 1.5))
    ctx.fillPath()

    // "zzz" text for sleeping vibe
    let zzz = "zzz" as NSString
    let zFont = NSFont.systemFont(ofSize: s * 0.065, weight: .bold)
    let zAttrs: [NSAttributedString.Key: Any] = [
        .font: zFont,
        .foregroundColor: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7),
    ]
    ctx.saveGState()
    ctx.translateBy(x: bunnyX + s * 0.12, y: headY + headR + s * 0.02)
    ctx.rotate(by: 0.1)
    NSGraphicsContext.current?.shouldAntialias = true
    zzz.draw(at: .zero, withAttributes: zAttrs)
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func drawStar(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    let points = 4
    let path = CGMutablePath()
    for i in 0..<(points * 2) {
        let r = (i % 2 == 0) ? radius : radius * 0.4
        let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
        let x = cx + r * cos(angle)
        let y = cy + r * sin(angle)
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()
}

func savePNG(image: NSImage, size: Int, path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("Generated: \(path) (\(size)x\(size))")
}

// macOS icon sizes
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "."

for size in sizes {
    let icon = generateIcon(size: size)
    let path = "\(outputDir)/icon_\(size)x\(size).png"
    savePNG(image: icon, size: size, path: path)
}

print("Done! Generated \(sizes.count) icon sizes.")

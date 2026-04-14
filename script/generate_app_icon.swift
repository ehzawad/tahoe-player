#!/usr/bin/env swift

import AppKit
import Foundation

private let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let resourcesURL = rootURL.appending(path: "Resources", directoryHint: .isDirectory)
private let iconsetURL = resourcesURL.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
private let icnsURL = resourcesURL.appending(path: "AppIcon.icns")

private struct IconImage {
    let filename: String
    let pixels: Int
}

private let images = [
    IconImage(filename: "icon_16x16.png", pixels: 16),
    IconImage(filename: "icon_16x16@2x.png", pixels: 32),
    IconImage(filename: "icon_32x32.png", pixels: 32),
    IconImage(filename: "icon_32x32@2x.png", pixels: 64),
    IconImage(filename: "icon_128x128.png", pixels: 128),
    IconImage(filename: "icon_128x128@2x.png", pixels: 256),
    IconImage(filename: "icon_256x256.png", pixels: 256),
    IconImage(filename: "icon_256x256@2x.png", pixels: 512),
    IconImage(filename: "icon_512x512.png", pixels: 512),
    IconImage(filename: "icon_512x512@2x.png", pixels: 1024)
]

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for image in images {
    let rep = renderIcon(pixels: image.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw IconError.pngEncodingFailed(image.filename)
    }
    try png.write(to: iconsetURL.appending(path: image.filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconsetURL.path(percentEncoded: false),
    "-o", icnsURL.path(percentEncoded: false)
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw IconError.iconutilFailed(process.terminationStatus)
}

print("Generated \(icnsURL.path(percentEncoded: false))")

private enum IconError: Error, CustomStringConvertible {
    case pngEncodingFailed(String)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case .pngEncodingFailed(let filename):
            "Could not encode \(filename)"
        case .iconutilFailed(let status):
            "iconutil failed with status \(status)"
        }
    }
}

private func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    context.shouldAntialias = true

    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func drawIcon() {
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

    let baseRect = NSRect(x: 70, y: 70, width: 884, height: 884)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 220, yRadius: 220)

    let baseShadow = NSShadow()
    baseShadow.shadowOffset = NSSize(width: 0, height: -22)
    baseShadow.shadowBlurRadius = 44
    baseShadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
    baseShadow.set()

    NSGradient(
        starting: color(0x222832),
        ending: color(0x03070B)
    )!.draw(in: basePath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()
    NSGradient(
        starting: color(0x00B8FF, alpha: 0.55),
        ending: color(0x0A4D72, alpha: 0.03)
    )!.draw(in: NSRect(x: 92, y: 476, width: 840, height: 460), angle: -36)
    NSGradient(
        starting: color(0x7FE8FF, alpha: 0.32),
        ending: color(0xFFFFFF, alpha: 0.02)
    )!.draw(in: NSRect(x: 124, y: 654, width: 780, height: 210), angle: 18)
    NSGraphicsContext.restoreGraphicsState()

    color(0xFFFFFF, alpha: 0.16).setStroke()
    basePath.lineWidth = 4
    basePath.stroke()

    drawGlassPlate()
    drawPlayerGlyph()
}

private func drawGlassPlate() {
    let plateRect = NSRect(x: 188, y: 260, width: 648, height: 484)
    let platePath = NSBezierPath(roundedRect: plateRect, xRadius: 122, yRadius: 122)

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.shadowBlurRadius = 36
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    shadow.set()

    NSGradient(
        starting: color(0xFFFFFF, alpha: 0.28),
        ending: color(0xFFFFFF, alpha: 0.06)
    )!.draw(in: platePath, angle: -90)

    color(0x081018, alpha: 0.30).setFill()
    platePath.fill()

    color(0xFFFFFF, alpha: 0.24).setStroke()
    platePath.lineWidth = 3
    platePath.stroke()

    let shinePath = NSBezierPath(roundedRect: NSRect(x: 238, y: 630, width: 548, height: 62), xRadius: 31, yRadius: 31)
    color(0xFFFFFF, alpha: 0.20).setFill()
    shinePath.fill()
}

private func drawPlayerGlyph() {
    let backRect = NSRect(x: 286, y: 356, width: 350, height: 270)
    let backPath = NSBezierPath(roundedRect: backRect, xRadius: 58, yRadius: 58)
    color(0xFFFFFF, alpha: 0.10).setFill()
    backPath.fill()
    color(0xFFFFFF, alpha: 0.18).setStroke()
    backPath.lineWidth = 18
    backPath.stroke()

    let frontRect = NSRect(x: 360, y: 404, width: 364, height: 276)
    let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: 62, yRadius: 62)
    NSGradient(
        starting: color(0xA9F3FF, alpha: 0.95),
        ending: color(0x0A8BD4, alpha: 0.86)
    )!.draw(in: frontPath, angle: -90)
    color(0xFFFFFF, alpha: 0.40).setStroke()
    frontPath.lineWidth = 10
    frontPath.stroke()

    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: 494, y: 468))
    triangle.line(to: NSPoint(x: 494, y: 612))
    triangle.line(to: NSPoint(x: 618, y: 540))
    triangle.close()
    color(0xFFFFFF, alpha: 0.96).setFill()
    triangle.fill()

    let subtitleLine = NSBezierPath(roundedRect: NSRect(x: 438, y: 438, width: 208, height: 18), xRadius: 9, yRadius: 9)
    color(0xFFFFFF, alpha: 0.62).setFill()
    subtitleLine.fill()

    let controlDot = NSBezierPath(ovalIn: NSRect(x: 292, y: 292, width: 56, height: 56))
    color(0xFFFFFF, alpha: 0.82).setFill()
    controlDot.fill()

    let controlBar = NSBezierPath(roundedRect: NSRect(x: 386, y: 312, width: 340, height: 18), xRadius: 9, yRadius: 9)
    color(0xFFFFFF, alpha: 0.35).setFill()
    controlBar.fill()

    let progress = NSBezierPath(roundedRect: NSRect(x: 386, y: 312, width: 190, height: 18), xRadius: 9, yRadius: 9)
    color(0x66D9FF, alpha: 0.92).setFill()
    progress.fill()
}

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

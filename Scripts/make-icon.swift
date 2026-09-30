#!/usr/bin/env swift
// Draw the MacroPort icon, then build Resources/AppIcon.icns.
// Run it from the project folder: swift Scripts/make-icon.swift

import AppKit
import Foundation

let canvas: CGFloat = 1024        // every shape below uses this scale

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// The gamepad, with the D-pad and the buttons punched out of it.
func gamepad(scale: CGFloat) -> NSImage {
    let size = canvas * scale
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: scale, y: scale)

    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 240, y: 250, width: 544, height: 280),
                 xRadius: 120, yRadius: 120).fill()
    for x in [CGFloat(322), 702] {
        NSBezierPath(ovalIn: NSRect(x: x - 104, y: 174, width: 208, height: 208)).fill()
    }

    context.compositingOperation = .destinationOut
    NSColor.black.setFill()
    // the D-pad
    NSBezierPath(roundedRect: NSRect(x: 372, y: 336, width: 40, height: 128),
                 xRadius: 14, yRadius: 14).fill()
    NSBezierPath(roundedRect: NSRect(x: 328, y: 380, width: 128, height: 40),
                 xRadius: 14, yRadius: 14).fill()
    // the two buttons
    for x in [CGFloat(636), 724] {
        NSBezierPath(ovalIn: NSRect(x: x - 38, y: 362, width: 76, height: 76)).fill()
    }
    image.unlockFocus()
    return image
}

func draw(size: CGFloat) {
    let scale = size / canvas
    let context = NSGraphicsContext.current!
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: scale, y: scale)

    // the rounded background
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                             xRadius: 185, yRadius: 185)
    NSGradient(colors: [color(0x2D1B69), color(0x6C5CE7)])?
        .draw(in: plate, angle: 90)

    // the arrow, which shows the direction of an import
    color(0x67E8F9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 477, y: 672, width: 70, height: 170),
                 xRadius: 22, yRadius: 22).fill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 400, y: 684))
    head.line(to: NSPoint(x: 624, y: 684))
    head.line(to: NSPoint(x: 512, y: 556))
    head.close()
    head.fill()

    context.cgContext.scaleBy(x: 1 / scale, y: 1 / scale)
    gamepad(scale: scale).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
}

func png(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(size: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(filePath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                      (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(base)x\(base)\(suffix).png"
    try png(size: CGFloat(base * scale)).write(to: iconset.appending(path: name))
}

// Keep a large copy for a README or a listing.
try png(size: 1024).write(to: URL(filePath: "Resources/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(filePath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Built Resources/AppIcon.icns"
                                  : "iconutil failed: \(task.terminationStatus)")

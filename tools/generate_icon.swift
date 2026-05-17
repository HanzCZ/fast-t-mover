#!/usr/bin/env swift
// Render a 1024×1024 PNG app icon (SF Symbol on a rounded gradient square).
// Usage: swift tools/generate_icon.swift <output.png>

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_icon.swift <out.png>\n".utf8))
    exit(1)
}
let outPath = CommandLine.arguments[1]

let side: Int = 1024
let sideF = CGFloat(side)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 32
) else {
    FileHandle.standardError.write(Data("rep init failed\n".utf8))
    exit(2)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: sideF, height: sideF)
let cornerRadius = sideF * 0.225 // macOS squircle approximation

// Gradient background, clipped to squircle
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.65, alpha: 1)
])!
let clip = NSBezierPath(roundedRect: rect,
                        xRadius: cornerRadius, yRadius: cornerRadius)
NSGraphicsContext.current?.saveGraphicsState()
clip.addClip()
gradient.draw(in: rect, angle: -90)

// Subtle inner highlight on top half
let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.18),
    NSColor.white.withAlphaComponent(0.0)
])!
highlight.draw(in: NSRect(x: 0, y: sideF * 0.5,
                          width: sideF, height: sideF * 0.5), angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

// SF Symbol foreground
let symbolName = "externaldrive.fill.badge.plus"
let symbolPointSize: CGFloat = sideF * 0.58
let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
    .withSymbolConfiguration(config)
{
    let symSize = symbol.size
    let drawRect = NSRect(
        x: (sideF - symSize.width) / 2,
        y: (sideF - symSize.height) / 2 - sideF * 0.02,
        width: symSize.width, height: symSize.height
    )
    symbol.draw(in: drawRect)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("png encode failed\n".utf8))
    exit(3)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")

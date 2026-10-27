import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = size / 1024

    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.33, blue: 0.70, alpha: 1),
    ])?.draw(in: tilePath, angle: 90)

    let windowColors: [NSColor] = [
        NSColor(calibratedWhite: 1, alpha: 0.22),
        NSColor(calibratedWhite: 1, alpha: 0.32),
        NSColor(calibratedWhite: 1, alpha: 0.45),
    ]
    for (index, color) in windowColors.enumerated() {
        let offset = CGFloat(index) * 70 * unit
        let rect = NSRect(x: 250 * unit + offset, y: 600 * unit - offset, width: 380 * unit, height: 230 * unit)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 28 * unit, yRadius: 28 * unit).fill()
    }

    let bar = NSRect(x: 190 * unit, y: 190 * unit, width: 644 * unit, height: 150 * unit)
    NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 48 * unit, yRadius: 48 * unit).fill()

    let slots: [(CGFloat, NSColor)] = [
        (230, NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.25, alpha: 1)),
        (370, NSColor(calibratedRed: 0.36, green: 0.84, blue: 0.62, alpha: 1)),
        (510, NSColor(calibratedRed: 0.36, green: 0.84, blue: 0.62, alpha: 1)),
        (650, NSColor(calibratedRed: 0.55, green: 0.70, blue: 1.00, alpha: 1)),
    ]
    for (x, color) in slots {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x * unit, y: 222 * unit, width: 104 * unit, height: 86 * unit), xRadius: 20 * unit, yRadius: 20 * unit).fill()
    }
    NSColor.white.setFill()
    for x in [282.0, 422.0, 562.0, 702.0] {
        NSBezierPath(ovalIn: NSRect(x: (x - 7) * unit, y: 200 * unit, width: 14 * unit, height: 14 * unit)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in variants {
    guard let data = render(pixels) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: output.appendingPathComponent("\(name).png"))
}

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: export-app-icon <AppIcon.icon> <output.png>\n", stderr)
  exit(2)
}

let iconDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard
  let drawingContext = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  )
else {
  fputs("unable to create RGB bitmap\n", stderr)
  exit(1)
}
let context = NSGraphicsContext(cgContext: drawingContext, flipped: false)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(
  calibratedRed: 8.0 / 255.0,
  green: 28.0 / 255.0,
  blue: 54.0 / 255.0,
  alpha: 1
).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let layerNames = [
  "03-health-and-home.svg",
  "02-health-to-home.svg",
  "01-home-to-health.svg",
]

for layerName in layerNames {
  let layerURL = iconDirectory.appendingPathComponent("Assets/").appendingPathComponent(layerName)
  guard let image = NSImage(contentsOf: layerURL) else {
    fputs("unable to load \(layerURL.path)\n", stderr)
    exit(1)
  }
  image.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
  )
}

drawingContext.flush()
NSGraphicsContext.restoreGraphicsState()

guard let renderedImage = drawingContext.makeImage() else {
  fputs("unable to read rendered image\n", stderr)
  exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: renderedImage)
guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
  fputs("unable to encode PNG\n", stderr)
  exit(1)
}

try png.write(to: outputURL, options: Data.WritingOptions.atomic)

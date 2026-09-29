import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: verify-app-icon-visual <compiled-icon.png>\n", stderr)
  exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard
  let image = NSImage(contentsOf: imageURL),
  let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  fputs("could not decode compiled app icon\n", stderr)
  exit(2)
}

let width = source.width
let height = source.height
var bytes = [UInt8](repeating: 0, count: width * height * 4)

guard let context = CGContext(
  data: &bytes,
  width: width,
  height: height,
  bitsPerComponent: 8,
  bytesPerRow: width * 4,
  space: CGColorSpaceCreateDeviceRGB(),
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
  fputs("could not create image analysis context\n", stderr)
  exit(2)
}

context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

var coloredPixelCount = 0
var minX = width
var minY = height
var maxX = -1
var maxY = -1
var coloredLuminances: [Double] = []

for y in 0..<height {
  for x in 0..<width {
    let offset = (y * width + x) * 4
    let red = Double(bytes[offset]) / 255
    let green = Double(bytes[offset + 1]) / 255
    let blue = Double(bytes[offset + 2]) / 255

    let isCoral = red > 0.65 && red - green > 0.15 && red - blue > 0.12
    let isCyan = green > 0.58 && blue > 0.55 && green - red > 0.14 && blue - red > 0.12

    guard isCoral || isCyan else { continue }

    coloredPixelCount += 1
    minX = min(minX, x)
    minY = min(minY, y)
    maxX = max(maxX, x)
    maxY = max(maxY, y)
    coloredLuminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
  }
}

guard coloredPixelCount > 0 else {
  fputs("compiled icon has no coral or cyan foreground\n", stderr)
  exit(1)
}

coloredLuminances.sort()
let boundingWidth = Double(maxX - minX + 1) / Double(width)
let boundingHeight = Double(maxY - minY + 1) / Double(height)
let coloredCoverage = Double(coloredPixelCount) / Double(width * height)
let luminanceSpread =
  coloredLuminances[coloredLuminances.count * 9 / 10]
  - coloredLuminances[coloredLuminances.count / 10]

let summary = String(
  format: "foreground bbox %.3f x %.3f, coverage %.3f, luminance spread %.3f",
  boundingWidth,
  boundingHeight,
  coloredCoverage,
  luminanceSpread
)

guard boundingWidth >= 0.88, boundingHeight >= 0.70 else {
  fputs("app icon foreground is too small: \(summary)\n", stderr)
  exit(1)
}

guard boundingWidth <= 0.94 else {
  fputs("app icon foreground reaches too close to the mask edge: \(summary)\n", stderr)
  exit(1)
}

guard coloredCoverage >= 0.20 else {
  fputs("app icon foreground lacks visual weight: \(summary)\n", stderr)
  exit(1)
}

guard luminanceSpread >= 0.29 else {
  fputs("app icon foreground lacks gradient depth: \(summary)\n", stderr)
  exit(1)
}

print(summary)

import AppKit

guard CommandLine.arguments.count == 3 else {
  fputs("usage: make-ohos-dev-icon.swift input.png output.png\\n", stderr)
  exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: inputURL) else {
  fputs("cannot load \\(inputURL.path)\\n", stderr)
  exit(1)
}

let size = NSSize(width: 1280, height: 1280)
let image = NSImage(size: size)
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: source.size), operation: .sourceOver, fraction: 1)

let badgeRect = NSRect(x: 768, y: 76, width: 412, height: 206)
NSColor(calibratedRed: 0.05, green: 0.64, blue: 0.96, alpha: 0.96).setFill()
NSBezierPath(roundedRect: badgeRect, xRadius: 50, yRadius: 50).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.monospacedSystemFont(ofSize: 132, weight: .bold),
  .foregroundColor: NSColor.white,
  .paragraphStyle: paragraph,
]
let label = NSAttributedString(string: "DEV", attributes: attributes)
label.draw(in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 31, width: badgeRect.width, height: 144))
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("cannot encode PNG\\n", stderr)
  exit(1)
}
try png.write(to: outputURL)

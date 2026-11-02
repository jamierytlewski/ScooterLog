import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Shared/AppIcon.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = root.appendingPathComponent(
    "Shared/AppIcon.xcassets/AppIconAres.appiconset/AppIconAres.png")
guard let image = NSBitmapImageRep(data: try Data(contentsOf: source)),
    let output = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: image.pixelsWide, pixelsHigh: image.pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("The source icon couldn't be decoded.") }

for y in 0..<image.pixelsHigh {
    for x in 0..<image.pixelsWide {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            fatalError("A source icon pixel couldn't be decoded.")
        }
        let hue = color.hueComponent
        // Recolor the cyan scooter and trail while retaining the midnight backdrop and red tail light.
        var result = color
        if hue > 0.35 && hue < 0.95 {
            let amount = min(1, max(0, (color.brightnessComponent - 0.08) / 0.22))
            let hueWeight = min(1, min((hue - 0.35) / 0.10, (0.95 - hue) / 0.10))
            let blend = amount * amount * (3 - 2 * amount) * hueWeight
            let red = NSColor(
                calibratedHue: 0.01, saturation: color.saturationComponent,
                brightness: color.brightnessComponent, alpha: 1)
            result = NSColor(
                calibratedRed: color.redComponent * (1 - blend) + red.redComponent * blend,
                green: color.greenComponent * (1 - blend) + red.greenComponent * blend,
                blue: color.blueComponent * (1 - blend) + red.blueComponent * blend,
                alpha: 1)
        }
        var pixel = [
            Int((result.redComponent * 255).rounded()),
            Int((result.greenComponent * 255).rounded()),
            Int((result.blueComponent * 255).rounded()),
        ]
        output.setPixel(&pixel, atX: x, y: y)
    }
}
guard let data = output.representation(using: .png, properties: [:]) else {
    fatalError("The Ares icon couldn't be encoded.")
}
try data.write(to: destination)
try data.write(to: root.appendingPathComponent("Shared/Assets.xcassets/ScooterRed.imageset/ScooterRed.png"))
try Data(contentsOf: source).write(
    to: root.appendingPathComponent("Shared/Assets.xcassets/ScooterBlue.imageset/ScooterBlue.png"))
print("Wrote \(destination.lastPathComponent)")

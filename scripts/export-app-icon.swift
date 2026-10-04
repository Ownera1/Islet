#!/usr/bin/env swift
// Export the selected B artwork to the macOS asset catalog without changing its inner design.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/export-app-icon.swift <selected-B.png> (from repository root)")
}
let files = FileManager.default
let root = URL(fileURLWithPath: files.currentDirectoryPath)
let input = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height, artwork.width >= 1024 else {
    fatalError("Expected a square PNG master at least 1024 pixels wide")
}
let assets = root.appendingPathComponent("boringNotch/Assets.xcassets")
let catalog = assets.appendingPathComponent("AppIcon.appiconset")
let oldContents = try Data(contentsOf: catalog.appendingPathComponent("Contents.json"))
let oldImages = (try JSONSerialization.jsonObject(with: oldContents) as! [String: Any])["images"] as! [[String: String]]

func export(_ pixels: Int, to destination: URL) throws {
    let side = CGFloat(pixels)
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot create PNG context") }
    // A standard inset tile clips the generated alpha fringe. Inner artwork stays untouched.
    let tile = CGRect(x: side * 0.083, y: side * 0.083,
                      width: side * 0.834, height: side * 0.834)
    let radius = tile.width * 0.22
    context.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    // Keep the tile opaque even if the generated PNG contains nearly opaque interior pixels.
    context.setFillColor(CGColor(red: 253.0 / 255, green: 249.0 / 255, blue: 241.0 / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.interpolationQuality = .high
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let rendered = context.makeImage(),
          let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot create PNG destination") }
    CGImageDestinationAddImage(writer, rendered, nil)
    guard CGImageDestinationFinalize(writer) else { fatalError("PNG export failed") }
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try export(size * scale, to: catalog.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
var encoded = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
encoded.append(0x0a)
try encoded.write(to: catalog.appendingPathComponent("Contents.json"))
let usedNames = Set(images.compactMap { $0["filename"] })
for image in oldImages {
    if let filename = image["filename"], !usedNames.contains(filename) {
        try files.removeItem(at: catalog.appendingPathComponent(filename))
    }
}

let logo = assets.appendingPathComponent("logo2.imageset")
try export(512, to: logo.appendingPathComponent("AgentUsageNotch.png"))
let logoContents: [String: Any] = [
    "images": [["filename": "AgentUsageNotch.png", "idiom": "universal"]],
    "info": ["author": "xcode", "version": 1]
]
var logoData = try JSONSerialization.data(withJSONObject: logoContents, options: [.prettyPrinted, .sortedKeys])
logoData.append(0x0a)
try logoData.write(to: logo.appendingPathComponent("Contents.json"))
let oldLogo = logo.appendingPathComponent("BoringNotch icon.png")
if files.fileExists(atPath: oldLogo.path) { try files.removeItem(at: oldLogo) }
print("Exported 10 macOS icon representations and the onboarding/settings logo")

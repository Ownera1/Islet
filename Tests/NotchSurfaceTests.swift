import AppKit
import SwiftUI

@main
struct NotchSurfaceTestRunner {
    @MainActor
    static func main() throws {
        // Render the production surface with the different intrinsic heights
        // supplied by Home, lyrics focus and configurable header heights.
        for scale: CGFloat in [1, 2] {
            for contentHeight: CGFloat in [158, 172, 186, 194] {
                let view = Color.clear
                    .frame(width: 640, height: contentHeight)
                    .modifier(NotchSurface(
                        shape: NotchShape(topCornerRadius: 19, bottomCornerRadius: 24),
                        height: 190, topCornerRadius: 19
                    ))
                let bitmap = try render(view, scale: scale)
                precondition(bitmap.pixelsHigh == Int(190 * scale))
                for y in 0..<bitmap.pixelsHigh {
                    let pixel = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)!
                    precondition(pixel.alphaComponent > 0.99,
                                 "Transparent seam at y=\(y), content=\(contentHeight), scale=\(scale)")
                    precondition(pixel.redComponent < 0.01 && pixel.greenComponent < 0.01 && pixel.blueComponent < 0.01)
                }
                precondition(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1)!.alphaComponent < 0.01,
                             "The rounded corner must remain transparent")
            }

            let marker = Color.red.frame(width: 640, height: 24)
                .modifier(NotchSurface(
                    shape: NotchShape(topCornerRadius: 19, bottomCornerRadius: 24),
                    height: 190, topCornerRadius: 19
                ))
            let markerBitmap = try render(marker, scale: scale)
            precondition(markerBitmap.colorAt(x: Int(320 * scale), y: Int(2 * scale))!.redComponent > 0.99,
                         "The header must stay attached to the top")
            precondition(markerBitmap.colorAt(x: Int(320 * scale), y: Int(30 * scale))!.redComponent < 0.01)

            let closed = Color.clear.frame(width: 185, height: 32)
                .modifier(NotchSurface(
                    shape: NotchShape(), height: nil, topCornerRadius: 6
                ))
            let closedBitmap = try render(closed, scale: scale)
            precondition(closedBitmap.pixelsHigh == Int(32 * scale),
                         "The closed notch must retain its intrinsic height")
        }
        print("Passed 12 notch surface rendering cases at 1x and 2x.")
    }

    @MainActor
    private static func render<V: View>(_ view: V, scale: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else {
            throw NSError(domain: "NotchSurfaceTests", code: 1)
        }
        return NSBitmapImageRep(cgImage: image)
    }
}

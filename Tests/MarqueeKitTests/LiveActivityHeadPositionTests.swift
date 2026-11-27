import CoreText
import SwiftUI
import XCTest
@testable import MarqueeKit

final class LiveActivityHeadPositionTests: XCTestCase {
    @MainActor
    func testFirstGlyphStaysAtTheSamePixelWhenTheClockReachesTheNextCopy() throws {
        let label = Text(verbatim: "H Marquee").font(.system(size: 17, weight: .medium))
        let scale: CGFloat = 3
        let widthRenderer = ImageRenderer(content: label.fixedSize())
        widthRenderer.scale = scale
        let shapedWidth = try XCTUnwrap(widthRenderer.uiImage).size.width
        // Reproduce a disagreement between the rendered copy pitch and the
        // distance encoded by the clock. Joining the copies shifts the head by 16 pt.
        let period = shapedWidth + 16
        let inset: CGFloat = 12
        let viewport: CGFloat = 48
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WidgetMarqueePlayback", withExtension: "woff2"))
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let data = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let face = CTFontCreateWithGraphicsFont(try XCTUnwrap(CGFont(data)), 14, nil, nil)
        let ruler = Font(WidgetMarqueePlayback.font(face, period: period, travelDuration: 4, pause: 2, timing: .linear))
        let marquee = LiveActivityMarquee("H Marquee", startedAt: .distantPast)

        func firstInkColumn(at stamp: String) throws -> Int {
            let view = marquee.anchoredCopies(label, clock: Text(verbatim: stamp), ruler: ruler, count: 2,
                                             prefixPeriods: 1, period: period, width: viewport, inset: inset)
                .foregroundStyle(.white)
                .background(.black)
                .environment(\.displayScale, scale)
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height)
            return try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                      bitsPerComponent: 8, bytesPerRow: image.width,
                                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return try XCTUnwrap((0..<image.width).first { x in
                    (0..<image.height).contains { y in bytes[y * image.width + x] > 128 }
                }, "Missing first glyph at \(stamp)")
            }
        }

        let head = try firstInkColumn(at: "0:00.00")
        XCTAssertGreaterThanOrEqual(head, Int(inset * scale) - 1)
        XCTAssertLessThan(head, Int((inset + 5) * scale))
        XCTAssertLessThan(try firstInkColumn(at: "0:00.20"), head - 4)
        for stamp in ["0:04.00", "0:05.75", "0:06.00"] {
            XCTAssertEqual(try firstInkColumn(at: stamp), head, "First glyph moved at \(stamp)")
        }
    }
}

import CoreText
import SwiftUI
import XCTest
@testable import MarqueeKit

final class LiveActivityHeadPositionTests: XCTestCase {
    @MainActor
    func testHeadPositionAndBrightnessAcrossTwoRestarts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WidgetMarqueePlayback", withExtension: "woff2"))
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let base = CTFontCreateWithGraphicsFont(try XCTUnwrap(CGFont(provider)), 14, nil, nil)
        let label = "H Marquee — 次の周回"
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        let inset: CGFloat = 12
        for gap: CGFloat? in [nil, 0, 0.5, 64] {
            let marquee = LiveActivityMarquee(label, startedAt: .distantPast, horizontalFont: font, repeatSpacing: gap)
            let nominal = WidgetMarqueeMetrics.liveRepeatWidth(for: label, font: font, repeatSpacing: gap)
            let period = marquee.renderedRepeatWidth(for: label, fallback: nominal)
            let prefix = (gap ?? nominal - WidgetMarqueeMetrics.textWidth(for: label, font: font)) < inset ? 2 : 1
            let ruler = Font(WidgetMarqueePlayback.font(base, period: period, travelDuration: 4, pause: 2, timing: .linear))
            func image(_ stamp: String) throws -> [UInt8] {
                let view = marquee.horizontalStrip(label, clock: Text(verbatim: stamp), units: prefix, ruler: ruler,
                                                   prefixPeriods: prefix, period: period, width: 48, inset: inset)
                    .foregroundStyle(.white).background(.black).environment(\.displayScale, 3)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.cgImage)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height)
                try pixels.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                          bitsPerComponent: 8, bytesPerRow: image.width,
                                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                }
                return pixels
            }
            let head = try image("0:00.00")
            let mass = head.reduce(0) { $0 + Int($1) }
            XCTAssertGreaterThan(mass, 0)
            let width = 48 * 3
            // Register the glyphs at device-pixel resolution before comparing ink.
            // Fractional origins change antialiasing even at the same logical head.
            func alignmentError(_ compared: [UInt8], shift: Int) -> Double {
                var delta = 0
                for pixel in head.indices where (4..<(width - 4)).contains(pixel % width) {
                    delta += abs(Int(head[pixel]) - Int(compared[pixel + shift]))
                }
                return Double(delta) / Double(max(mass, 1))
            }
            XCTAssertGreaterThan(try alignmentError(image("0:00.30"), shift: 0), 0.15)
            for stamp in ["0:04.00", "0:05.99", "0:06.00", "0:11.99", "0:12.00"] {
                let frame = try image(stamp)
                let ink = frame.reduce(0) { $0 + Int($1) }
                XCTAssertEqual(Double(ink) / Double(mass), 1, accuracy: 0.05,
                               "Ink at \(stamp), gap \(String(describing: gap))")
                let errors = (-3...3).map { alignmentError(frame, shift: $0) }
                XCTAssertLessThan(try XCTUnwrap(errors.min()), 0.12,
                                  "Alignment at \(stamp), gap \(String(describing: gap))")
            }
        }
    }
}

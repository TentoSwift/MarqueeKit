import CoreText
import SwiftUI
import XCTest
@testable import MarqueeKit

final class LiveActivityCruiseTests: XCTestCase {
    @MainActor
    func testMovingGlyphsMatchOneNativeTextAtTheirScheduledPosition() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WidgetMarqueePlayback", withExtension: "woff2"))
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let base = CTFontCreateWithGraphicsFont(try XCTUnwrap(CGFont(provider)), 14, nil, nil)
        let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let width: CGFloat = 72
        let height = max(23, ceil(font.lineHeight))
        let period: CGFloat = 128
        let ruler = Font(WidgetMarqueePlayback.font(base, period: period, travelDuration: 4, pause: 4, timing: .linear,
                                                    spansTwoLaps: true))
        for line in ["HIIH HIIH HIIH 文字の輪郭", "HIIH 🟩 HIIH 東京 🟦"] {
            let marquee = LiveActivityMarquee(line, startedAt: .distantPast, horizontalFont: font)
            // Deliberately separate the timestamps by half a second. At 32 pt/s
            // two painted samples would be visibly distinct. The two advances
            // must place a single copy exactly at the midpoint (16 or 40 pt).
            for (early, late, distance): (String, String, CGFloat) in [("0:00.25", "0:00.75", 16), ("0:01.00", "0:01.50", 40)] {
                let clock = LiveActivityMarquee.clockPrefix(Text(verbatim: early), Text(verbatim: late), base: base)
                let moving = marquee.horizontalStrip(line, clock: clock, units: 2, ruler: ruler,
                                                     prefixPeriods: 2, period: period, width: width, inset: 0)
                let reference = Text(verbatim: line).font(Font(font)).lineLimit(1)
                    .frame(width: 3 * period + 2, height: height, alignment: .leading)
                    .offset(x: -distance)
                    .frame(width: width, height: height, alignment: .leading).clipped()
                let actual = try pixels(moving)
                let expected = try pixels(reference)
                XCTAssertEqual(actual.count, expected.count)
                var difference = 0
                var referenceInk = 0
                for index in expected.indices where index % 4 != 3 {
                    difference += abs(Int(actual[index]) - Int(expected[index]))
                    referenceInk += Int(expected[index])
                }
                XCTAssertGreaterThan(referenceInk, 0)
                XCTAssertLessThan(Double(difference) / Double(max(1, referenceInk)), 0.03, "\(line), \(early)–\(late)")
            }
        }
    }

    @MainActor
    private func pixels(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.foregroundStyle(.white.opacity(0.55)).background(.black)
            .environment(\.displayScale, 3))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}

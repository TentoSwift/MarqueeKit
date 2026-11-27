import CoreText
import SwiftUI
import XCTest
@testable import WidgetMarquee

final class LiveActivityStopwatchFontTests: XCTestCase {
    private let period: CGFloat = 240

    private func stopwatchFont() throws -> CTFont {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WidgetMarqueeStopwatch", withExtension: "ttf"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let graphicsFont = try XCTUnwrap(CGFont(provider))
        let font = CTFontCreateWithGraphicsFont(graphicsFont, period / 24, nil, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "WidgetMarqueeStopwatch-Regular")
        return font
    }

    #if canImport(SwiftUICore)
    func testSystemStopwatchAdvancesAtEveryCentisecondAndWraps() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("The native stopwatch requires iOS 18.") }
        let font = try stopwatchFont()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let format = SystemFormatStyle.Stopwatch(
            startingAt: start, showsHours: false, maxFieldCount: 4, maxPrecision: .milliseconds(10)
        ).locale(Locale(identifier: "en_US_POSIX"))

        // Sample fixed instants inside the centisecond, including minute and hour rollovers.
        for tick in Array(0...1_000) + [5_999, 6_000, 359_999, 360_000, 2_879_999, 2_880_000] {
            let date = start.addingTimeInterval(Double(tick) / 100 + 0.001)
            let stamp = String(format.format(date).characters)
            let clock = NSAttributedString(string: stamp, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(clock)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let expected = period * CGFloat(999 - tick % 1_000) / 1_000
            XCTAssertEqual(width, expected, accuracy: 0.002, stamp)
        }
    }
    #endif

    func testClockMovesTheVisibleMessageIncludingRightToLeftText() throws {
        let clockFont = try stopwatchFont()
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        func position(of text: String, after stamp: String) -> CGFloat {
            let prefix = "\u{200E}" + stamp
            let result = NSMutableAttributedString(string: prefix, attributes: [.font: clockFont])
            result.append(NSAttributedString(string: text, attributes: [.font: bodyFont]))
            let line = CTLineCreateWithAttributedString(result)
            // Measure inside the message to avoid the bidi boundary between the two runs.
            return CTLineGetOffsetForStringIndex(line, prefix.utf16.count + 1, nil)
        }

        for text in ["京都 👩🏽‍🚀 Cafe\u{301}", "مرحبا بالعالم", "שלום עולם"] {
            let distance = position(of: text, after: "00:00.00") - position(of: text, after: "00:05.00")
            XCTAssertEqual(distance, period / 2, accuracy: 0.002, text)
        }
    }
}

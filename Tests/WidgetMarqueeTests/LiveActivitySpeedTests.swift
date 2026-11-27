import CoreText
import SwiftUI
import XCTest
@testable import WidgetMarquee

final class LiveActivitySpeedTests: XCTestCase {
    @MainActor
    private func speedFont(period: CGFloat, speed: CGFloat) throws -> CTFont {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WidgetMarqueeSpeed", withExtension: "ttf"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let graphics = try XCTUnwrap(CGFont(provider))
        let base = CTFontCreateWithGraphicsFont(graphics, 14, nil, nil)
        return LiveActivityMarquee.speedFont(base, period: period, pointsPerSecond: speed)
    }

    private func advance(_ stamp: String, font: CTFont) -> CGFloat {
        let string = NSAttributedString(string: stamp, attributes: [.font: font])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil))
    }

    // A carry may put a different copy of the same text in the viewport.
    private func assertDistance(_ distance: CGFloat, equals expected: CGFloat, period: CGFloat, stamp: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let error = (distance - expected).remainder(dividingBy: period)
        XCTAssertEqual(error, 0, accuracy: period * 0.0004, stamp, file: file, line: line)
    }

    #if canImport(SwiftUICore)
    @MainActor
    func testNativeStopwatchTracksRequestedPointsPerSecondThroughCarries() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("The native stopwatch requires iOS 18.") }
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let format = SystemFormatStyle.Stopwatch(
            startingAt: start, showsHours: true, maxFieldCount: 4, maxPrecision: .milliseconds(10)
        ).locale(Locale(identifier: "en_US_POSIX"))
        let ticks = [0, 1, 9, 10, 99, 100, 999, 1_000, 5_999, 6_000, 59_999, 60_000,
                     359_999, 360_000, 2_879_999, 2_880_000]
        for (period, speed): (CGFloat, CGFloat) in [(363.5, 17.25), (363.5, 60), (801.75, 60)] {
            let font = try speedFont(period: period, speed: speed)
            let origin = advance(String(format.format(start).characters), font: font)
            for tick in ticks {
                let seconds = Double(tick) / 100
                let date = start.addingTimeInterval(seconds + 0.001)
                let stamp = String(format.format(date).characters)
                assertDistance(origin - advance(stamp, font: font), equals: CGFloat(seconds) * speed,
                               period: period, stamp: stamp)
            }
        }
    }
    #endif

    @MainActor
    func testWholeSecondTimerUsesTheSameSpeedAcrossHours() throws {
        let period: CGFloat = 394.75
        let speed: CGFloat = 37.5
        let font = try speedFont(period: period, speed: speed)
        let origin = advance("0:00", font: font)
        let stamps = [("0:01", 1), ("0:59", 59), ("1:00", 60), ("59:59", 3_599),
                      ("1:00:00", 3_600), ("7:59:59", 28_799), ("8:00:00", 28_800)]
        for (stamp, seconds) in stamps {
            assertDistance(origin - advance(stamp, font: font), equals: CGFloat(seconds) * speed,
                           period: period, stamp: stamp)
        }
    }

    func testEasedAndLinearPassesHoldAtTheHeadAndRestartAcrossClockCarries() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "WidgetMarqueePlayback", withExtension: "ttf"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let graphics = try XCTUnwrap(CGFont(provider))
        let base = CTFontCreateWithGraphicsFont(graphics, 14, nil, nil)
        let period: CGFloat = 505
        let travel = 7.25
        let pause = 2.75
        let stamps: [(String, Double)] = [
            ("0:00.00", 0), ("0:00.20", 0.2), ("0:01.00", 1), ("0:03.62", 3.62),
            ("0:06.00", 6), ("0:07.20", 7.2), ("0:07.55", 7.55), ("0:09.99", 9.99),
            ("0:10.00", 10), ("0:10.20", 10.2), ("0:59.99", 59.99), ("1:00.00", 60),
            ("0:02", 2), ("0:07", 7), ("0:08", 8), ("1:00:00.20", 3600.2),
            ("7:59:59", 28799), ("8:00:00", 28800)
        ]
        for timing in [WidgetMarqueeTiming.linear, .easeInOut] {
            let font = WidgetMarqueePlayback.font(base, period: period, travelDuration: travel, pause: pause, timing: timing)
            for (stamp, seconds) in stamps {
                let local = seconds.truncatingRemainder(dividingBy: travel + pause)
                let fraction = min(local / travel, 1)
                let expected = Double(period) * (1 - timing.progress(fraction))
                let width = advance(stamp, font: font)
                XCTAssertEqual(width, expected, accuracy: 0.6, stamp)
                if local > travel { XCTAssertEqual(width, 0, accuracy: 0.001, stamp) }
            }
        }
    }
}

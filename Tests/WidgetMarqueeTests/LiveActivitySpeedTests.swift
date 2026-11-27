import CoreText
import SwiftUI
import XCTest
@testable import WidgetMarquee

final class LiveActivitySpeedTests: XCTestCase {
    private func bundledFont(_ name: String) throws -> CTFont {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ttf"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let graphics = try XCTUnwrap(CGFont(provider))
        return CTFontCreateWithGraphicsFont(graphics, 14, nil, nil)
    }

    @MainActor
    private func speedFont(period: CGFloat, speed: CGFloat) throws -> CTFont {
        LiveActivityMarquee.speedFont(try bundledFont("WidgetMarqueeSpeed"), period: period, pointsPerSecond: speed)
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
        let base = try bundledFont("WidgetMarqueePlayback")
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

    @MainActor
    func testEasedGroupClockTracksEachRowsOwnBrakingAndTheSharedRestart() throws {
        let base = try bundledFont("WidgetMarqueePlayback")
        let texts = ["東京から Kyoto", "東京から 京都を経由して 大阪へ",
                     "東京から 京都を経由して 大阪へ向かう列車です"]
        let speed: CGFloat = 55
        let group = WidgetMarqueeGroup(texts, startedAt: .distantPast, pointsPerSecond: speed,
                                       timing: .easeInOut, pauseBetweenLoops: 2, viewportWidth: 20)
        let periods = texts.map { WidgetMarqueeMetrics.liveRepeatWidth(for: $0) }
        let travel = group.rows.map(\.liveTravelDuration)
        let cycle = group.rows[0].liveCycleDuration
        let motions = try group.rows.map { try XCTUnwrap($0.liveMotion) }
        let rulers = group.rows.enumerated().map { index, row in
            WidgetMarqueePlayback.font(base, period: periods[index], travelDuration: travel[index], pause: 0,
                                       timing: row.timing, cycleDuration: cycle, groupMotion: motions[index])
        }
        let firstBrake = try XCTUnwrap(motions.map(\.decelerationStart).min())
        for tick in stride(from: 0, through: Int((cycle + travel[0]) * 100), by: 7) {
            let stamp = String(format: "%d:%02d.%02d", tick / 6000, tick / 100 % 60, tick % 100)
            let local = (Double(tick) / 100).truncatingRemainder(dividingBy: cycle)
            let distances = rulers.indices.map { periods[$0] - advance(stamp, font: rulers[$0]) }
            for index in rulers.indices {
                let expected = periods[index] * motions[index].progress(at: local)
                // Interpolation may straddle a braking boundary by one font sample.
                if local + cycle / 128 < firstBrake {
                    XCTAssertEqual(distances[index], distances.last!, accuracy: 0.1, stamp)
                }
                XCTAssertEqual(distances[index], expected, accuracy: 0.65, stamp)
            }
        }
    }

    @MainActor
    func testGroupFontsHoldShortRowThenRestartTogether() throws {
        let base = try bundledFont("WidgetMarqueePlayback")
        let texts = ["東京から 京都へ", "東京から 名古屋、京都を経由して 大阪へ 🚄"]
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let periods = texts.map { (($0 + "    ") as NSString).size(withAttributes: [.font: font]).width }
        let start = Date(timeIntervalSinceReferenceDate: 173.25)
        let group = WidgetMarqueeGroup(items: [
            .init(texts[0], pointsPerSecond: periods[0] / 3, viewportWidth: 50),
            .init(texts[1], pointsPerSecond: periods[1] / 5, timing: .easeInOut, viewportWidth: 50)
        ], startedAt: start, pointsPerSecond: 40, pauseBetweenLoops: 2.5)

        for (index, row) in group.rows.enumerated() {
            _ = LiveActivityMarquee(row)
            let travel = index == 0 ? 3.0 : 5.0
            XCTAssertEqual(row.startedAt, start)
            XCTAssertEqual(row.liveTravelDuration, travel, accuracy: 1e-9)
            XCTAssertEqual(row.liveCycleDuration, 7.5, accuracy: 1e-9)
            let ruler = WidgetMarqueePlayback.font(base, period: periods[index], travelDuration: row.liveTravelDuration,
                                                    pause: 0, timing: row.timing, cycleDuration: row.liveCycleDuration)
            // 3.50 and 4.50: only the long row moves. 5.50 and 7.49: both rest.
            // 7.75 and 60.25: both have restarted a quarter of a second ago.
            let stamps: [(String, Double)] = [
                ("0:00.50", 0.5), ("0:03.50", 3.5), ("0:04.50", 4.5),
                ("0:05.50", 5.5), ("0:07.49", 7.49), ("0:07.75", 0.25),
                ("0:14.99", 7.49), ("1:00.25", 0.25)
            ]
            for (stamp, elapsed) in stamps {
                let fraction = min(1, elapsed / travel)
                let expected = periods[index] * (1 - row.timing.progress(fraction))
                let actual = advance(stamp, font: ruler)
                XCTAssertEqual(actual, expected, accuracy: 0.5, "row \(index) at \(stamp)")
                if elapsed > travel { XCTAssertEqual(actual, 0, accuracy: 0.001) }
            }
        }
    }

    func testLongClockKeepsCruisingWhileShortClockStops() throws {
        let base = try bundledFont("WidgetMarqueePlayback")
        let periods: [CGFloat] = [212.5, 500]
        let speed: CGFloat = 50
        let travel = periods.map { Double($0 / speed) }
        let profiles = WidgetMarqueeGroup.Motion.profiles(for: travel, timings: [.easeInOut, .easeInOut])
        // In the 128-second cycle, 4.25 s falls halfway between native sample
        // knots. Moving the long row's knot to that stop would halve its speed.
        for cycle in [14.0, 128.0] {
            let rulers = try periods.indices.map { i in
                WidgetMarqueePlayback.font(base, period: periods[i], travelDuration: travel[i], pause: 0,
                                            timing: .easeInOut, cycleDuration: cycle,
                                            groupMotion: try XCTUnwrap(profiles[travel[i]]))
            }
            func moved(_ row: Int, from start: String, to end: String) -> CGFloat {
                advance(start, font: rulers[row]) - advance(end, font: rulers[row])
            }
            let cruise = moved(1, from: "0:02.00", to: "0:02.50")
            XCTAssertGreaterThan(cruise, speed * 0.5)
            XCTAssertEqual(moved(0, from: "0:02.00", to: "0:02.50"), cruise, accuracy: 0.08)
            for (start, end) in [("0:03.50", "0:04.00"), ("0:04.00", "0:04.50"), ("0:04.50", "0:05.00")] {
                XCTAssertEqual(moved(1, from: start, to: end), cruise, accuracy: 0.45, start)
            }
            XCTAssertLessThan(moved(0, from: "0:04.00", to: "0:04.50"), cruise * 0.6)
            XCTAssertEqual(advance("0:04.50", font: rulers[0]), 0, accuracy: 0.01)
            for ruler in rulers { XCTAssertEqual(advance("0:13.00", font: ruler), 0, accuracy: 0.001) }
            if cycle == 14 {
                // The fifth lap also passes the short arrival across the minute carry.
                XCTAssertEqual(moved(1, from: "0:59.75", to: "1:00.25"), cruise, accuracy: 0.45)
            }
        }
    }
}

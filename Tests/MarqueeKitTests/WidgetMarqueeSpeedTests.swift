import SwiftUI
import UIKit
import WidgetKit
import XCTest
@testable import MarqueeKit

final class WidgetMarqueeSpeedTests: XCTestCase {
    private let text = "京都発\n🚄 東京行き 01 / 02 / 03"

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func testMovementInPointsUsesTheRenderedWidthAndGap() throws {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let width = ceil((line as NSString).size(withAttributes: [.font: font]).width) + 28

        for speed: CGFloat in [7.25, 40, 83.5] {
            let schedule = WidgetMarqueeSchedule(for: text, pointsPerSecond: speed)
            let duration = try XCTUnwrap(schedule.passDuration)
            XCTAssertEqual(duration, Double(width / speed), accuracy: 1e-9)
            for start in [-10.0, 0, 12, 800_000_000] {
                let from = schedule.position(at: date(start), copy: 0)
                let to = schedule.position(at: date(start + 0.25), copy: 0)
                let distance = (to - from + 3).truncatingRemainder(dividingBy: 3) * Double(width)
                XCTAssertEqual(distance, Double(speed) * 0.25, accuracy: 1e-6)
            }
            XCTAssertEqual(schedule.position(at: date(duration), copy: 0), 1, accuracy: 1e-9)
            XCTAssertEqual(schedule.position(at: date(3 * duration), copy: 0), 0, accuracy: 1e-9)
        }
    }

    @MainActor
    func testAppEntryAndTimelineAcceptTheSameSpeed() throws {
        _ = WidgetMarquee(text, pointsPerSecond: 40)
        _ = WidgetMarquee(text, date: date(25), pointsPerSecond: 40)
        let entry = WidgetMarqueeEntry(text, date: date(25), pointsPerSecond: 40)
        _ = WidgetMarquee(entry)
        let timeline = WidgetMarquee.timeline(for: text, from: date(25), pointsPerSecond: 40)
        XCTAssertEqual(timeline.entries.count, 151)
        XCTAssertTrue(timeline.entries.allSatisfy { $0.text == text && $0.schedule.passDuration == entry.schedule.passDuration })
        let initial = try XCTUnwrap(timeline.entries.first)
        let reloaded = WidgetMarquee.timeline(for: text, from: date(146), pointsPerSecond: 40)
        let overlap = try XCTUnwrap(reloaded.entries.first)
        let match = try XCTUnwrap(timeline.entries.first { $0.date == overlap.date })
        XCTAssertEqual(match.schedule.position(at: match.date, copy: 1), overlap.schedule.position(at: overlap.date, copy: 1))
        XCTAssertLessThanOrEqual(initial.date, date(25))
    }

    func testInvalidSpeedsProvideAStationarySingleEntry() {
        for speed: CGFloat in [0, -1, .nan, .infinity, -.infinity, .leastNonzeroMagnitude] {
            let timeline = WidgetMarquee.timeline(for: text, from: date(12.5), pointsPerSecond: speed)
            XCTAssertEqual(timeline.entries.map(\.date), [date(12.5)])
            XCTAssertEqual(timeline.policy, .never)
            XCTAssertEqual(timeline.entries.first?.schedule.passDuration, 0)
        }
    }

    func testVeryFastAndSlowSpeedsHaveFinitePositionsAndBoundedTimelines() throws {
        for speed: CGFloat in [1e-240, 500, .greatestFiniteMagnitude] {
            let timeline = WidgetMarquee.timeline(for: text, from: date(800_000_000.125), pointsPerSecond: speed)
            XCTAssertEqual(timeline.entries.count, 151)
            let first = try XCTUnwrap(timeline.entries.first)
            let last = try XCTUnwrap(timeline.entries.last)
            XCTAssertGreaterThanOrEqual(last.date.timeIntervalSince(first.date), 75)
            let times = timeline.entries.map(\.date)
            XCTAssertTrue(zip(times, times.dropFirst()).allSatisfy(<))
            for entry in timeline.entries {
                let lane = entry.schedule.position(at: entry.date, copy: 2)
                XCTAssertTrue((0..<3).contains(lane))
                XCTAssertTrue(entry.schedule.copyCycle(at: entry.date, copy: 2).isFinite)
            }
        }
    }

    @MainActor
    func testTimingAndPauseWorkWithAndWithoutAnExplicitSpeed() throws {
        _ = WidgetMarquee(text, timing: .easeInOut)
        _ = WidgetMarquee(text, pauseBetweenLoops: 2)
        _ = WidgetMarquee(text, date: date(0), timing: .easeInOut, pauseBetweenLoops: 2)
        _ = WidgetMarquee(text, pointsPerSecond: 40, timing: .easeInOut, pauseBetweenLoops: 2)
        let entry = WidgetMarqueeEntry(text, timing: .easeInOut, pauseBetweenLoops: 2)
        let linear = WidgetMarqueeSchedule(for: text)
        let schedules = [
            entry.schedule,
            WidgetMarqueeSchedule(for: text, pointsPerSecond: 40, timing: .easeInOut, pauseBetweenLoops: 2),
        ]
        XCTAssertEqual(entry.schedule.stepsPerPass, linear.stepsPerPass)
        for schedule in schedules {
            let travel = try XCTUnwrap(schedule.passDuration)
            for (fraction, position) in [(0.0, 0.0), (0.25, 0.15625), (0.5, 0.5), (0.75, 0.84375)] {
                XCTAssertEqual(schedule.position(at: date(travel * fraction), copy: 0), position, accuracy: 1e-9)
            }
            for hold in [0.0, 0.375, 1.25, 2.0] {
                XCTAssertEqual(schedule.position(at: date(travel + hold), copy: 0), 1, accuracy: 1e-9)
            }
            XCTAssertEqual(schedule.position(at: date(travel + 2 + travel / 4), copy: 0), 1.15625, accuracy: 1e-9)
            XCTAssertEqual(schedule.position(at: date(-1), copy: 0).truncatingRemainder(dividingBy: 1), 0, accuracy: 1e-9)
        }
    }

    func testWidgetTimelineIncludesStopAndRestartAtTheTextHead() throws {
        let pause = 1.375
        let timeline = WidgetMarquee.timeline(for: text, from: date(1), pointsPerSecond: 40, timing: .easeInOut, pauseBetweenLoops: pause)
        let first = try XCTUnwrap(timeline.entries.first)
        let travel = try XCTUnwrap(first.schedule.passDuration)
        let times = timeline.entries.map { $0.date.timeIntervalSinceReferenceDate }
        let stop = try XCTUnwrap(times.first { abs($0 - travel) < 1e-8 })
        let restart = try XCTUnwrap(times.first { abs($0 - travel - pause) < 1e-8 })
        XCTAssertEqual(restart - stop, pause, accuracy: 1e-8)
        XCTAssertEqual(timeline.entries.count, 151)
        XCTAssertTrue(zip(times, times.dropFirst()).allSatisfy(<))
        for time in [stop, (stop + restart) / 2, restart] {
            XCTAssertEqual(first.schedule.position(at: date(time), copy: 0), 1, accuracy: 1e-9)
        }
    }

    func testWidgetMovesToStopBeforeHoldAndUsesTheShortRestartInterval() throws {
        let width = WidgetMarqueeMetrics.repeatWidth(for: WidgetMarqueeMetrics.line(from: text))
        let speed = width / 5.5
        for timing in [WidgetMarqueeTiming.linear, .easeInOut] {
            let timeline = WidgetMarquee.timeline(
                for: text, from: date(0), pointsPerSecond: speed, timing: timing, pauseBetweenLoops: 1.25
            )
            func entry(at time: Double) throws -> WidgetMarqueeEntry {
                try XCTUnwrap(timeline.entries.first { abs($0.date.timeIntervalSince(date(time))) < 1e-9 })
            }
            let approach = try entry(at: 4)
            let stop = try entry(at: 5.5)
            let hold = try entry(at: 6)
            let restart = try entry(at: 6.75)
            let moving = try entry(at: 8)
            let schedule = approach.schedule
            XCTAssertEqual(approach.nextDate, stop.date)
            XCTAssertNotNil(schedule.entryAnimation(from: approach.date, to: stop.date))
            XCTAssertEqual(stop.nextDate, hold.date)
            XCTAssertNil(schedule.entryAnimation(from: stop.date, to: hold.date))
            XCTAssertNil(schedule.entryAnimation(from: hold.date, to: restart.date))
            XCTAssertEqual(restart.nextDate, moving.date)
            XCTAssertNotNil(schedule.entryAnimation(from: restart.date, to: moving.date))
            if timing == .linear {
                XCTAssertEqual(schedule.entryAnimation(from: approach.date, to: stop.date), .linear(duration: 1.5))
                XCTAssertEqual(schedule.entryAnimation(from: restart.date, to: moving.date), .linear(duration: 1.25))
            }
            XCTAssertEqual(schedule.previousSample(before: stop.date), approach.date)
            XCTAssertEqual(schedule.previousSample(before: moving.date), restart.date)
            XCTAssertNil(WidgetMarqueeEntry(text, date: stop.date, schedule: schedule).nextDate)
        }
        XCTAssertNil(WidgetMarquee.timeline(for: text).entries.first?.nextDate)
    }

    func testInvalidPausesUseZeroAndDoNotAffectTheDefaultSchedule() {
        for pause: Double in [0, -1, .nan, .infinity] {
            let timeline = WidgetMarquee.timeline(for: text, from: date(1), pauseBetweenLoops: pause)
            XCTAssertEqual(timeline.entries.first?.schedule.pauseBetweenLoops, 0)
            XCTAssertEqual(timeline.entries.first?.schedule.timing, .linear)
            XCTAssertEqual(timeline.policy, .after(date(240)))
        }
    }
}

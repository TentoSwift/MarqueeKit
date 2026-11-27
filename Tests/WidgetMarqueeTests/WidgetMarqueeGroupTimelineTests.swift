import SwiftUI
import WidgetKit
import XCTest
@testable import WidgetMarquee

final class WidgetMarqueeGroupTimelineTests: XCTestCase {
    private let origin = Date(timeIntervalSinceReferenceDate: 25.375)

    private func group(timing: WidgetMarqueeTiming = .linear, pause: TimeInterval = 1.25) -> WidgetMarqueeGroup {
        let text = "京都発 🚄 東京行き | START 0123456789 END"
        let width = WidgetMarqueeMetrics.repeatWidth(for: text)
        return WidgetMarqueeGroup(items: [
            .init(text, pointsPerSecond: width / 5.25),
            .init(text, pointsPerSecond: width / 8.5),
            .init("静止", pointsPerSecond: 0)
        ], startedAt: origin, pointsPerSecond: 40, timing: timing, pauseBetweenLoops: pause)
    }

    @MainActor
    func testRowsFinishSeparatelyThenStartTogetherAtSharedEpoch() {
        for timing in [WidgetMarqueeTiming.linear, .easeInOut] {
            for pause in [0.0, 1.25] {
                let group = group(timing: timing, pause: pause)
                _ = WidgetMarquee(group.rows[0])
                let rows = WidgetMarqueeGroupEntry(group, date: origin).rows
                let short = rows[0].schedule
                let long = rows[1].schedule
                let cycle = 8.5 + pause
                XCTAssertEqual(short.cycleDuration, cycle)
                XCTAssertEqual(long.cycleDuration, cycle)
                for lap in [0, 1, 6] {
                    let start = origin.addingTimeInterval(Double(lap) * cycle)
                    let hold = start.addingTimeInterval(7)
                    XCTAssertEqual(short.position(at: hold, copy: 0), Double((lap + 1) % 3), accuracy: 1e-10)
                    XCTAssertEqual(long.position(at: hold, copy: 0), Double(lap % 3) + timing.progress(7 / 8.5), accuracy: 1e-10)
                    let restart = start.addingTimeInterval(cycle)
                    for (schedule, duration) in [(short, 5.25), (long, 8.5)] {
                        let head = Double((lap + 1) % 3)
                        XCTAssertEqual(schedule.position(at: start.addingTimeInterval(8.5), copy: 0), head, accuracy: 1e-10)
                        XCTAssertEqual(schedule.position(at: restart, copy: 0), head, accuracy: 1e-10)
                        XCTAssertEqual(schedule.position(at: restart.addingTimeInterval(0.5), copy: 0),
                                       head + timing.progress(0.5 / duration), accuracy: 1e-10)
                    }
                }
                XCTAssertEqual(short.position(at: origin.addingTimeInterval(-20), copy: 0), 0)
                XCTAssertEqual(rows[2].schedule.position(at: origin.addingTimeInterval(2), copy: 0), 0)
            }
        }
    }

    @MainActor
    func testSharedTimelinePublishesEveryStopAndRestartAcrossReloads() throws {
        let group = group(timing: .easeInOut)
        let timeline = group.timeline(from: origin.addingTimeInterval(-1))
        XCTAssertEqual(timeline.entries.count, 151)
        let dates = timeline.entries.map(\.date)
        XCTAssertTrue(zip(dates, dates.dropFirst()).allSatisfy(<))
        for elapsed in [0.0, 5.25, 8.5, 9.75, 15, 18.25, 19.5] {
            XCTAssertTrue(dates.contains(origin.addingTimeInterval(elapsed)), "t=\(elapsed)")
        }
        for (entry, next) in zip(timeline.entries, timeline.entries.dropFirst()) {
            XCTAssertEqual(entry.rows.map(\.text), group.rows.map(\.text))
            XCTAssertTrue(entry.rows.allSatisfy { $0.date == entry.date })
            XCTAssertEqual(entry.rows[0].nextDate, next.date)
            XCTAssertEqual(entry.rows[1].nextDate, next.date)
            XCTAssertNil(entry.rows[2].nextDate)
        }
        let stopped = try XCTUnwrap(timeline.entries.first { $0.date == origin.addingTimeInterval(5.25) })
        let next = try XCTUnwrap(stopped.rows[0].nextDate)
        XCTAssertNil(stopped.rows[0].schedule.entryAnimation(from: stopped.date, to: next))
        XCTAssertNotNil(stopped.rows[1].schedule.entryAnimation(from: stopped.date, to: next))

        let originalTimes = dates.map(\.timeIntervalSinceReferenceDate)
        let reloadTimes = group.timeline(from: origin.addingTimeInterval(60)).entries
            .map { $0.date.timeIntervalSinceReferenceDate }
        let from = try XCTUnwrap(reloadTimes.first)
        let through = try XCTUnwrap(originalTimes.last)
        let originalOverlap = originalTimes.filter { $0 >= from }
        let reloadedOverlap = reloadTimes.filter { $0 <= through }
        XCTAssertFalse(originalOverlap.isEmpty)
        XCTAssertEqual(originalOverlap, reloadedOverlap)
    }

    func testEmptyAndEntirelyStationaryGroupsUseOneEntry() {
        for messages in [[], ["", "短い"]] {
            let group = WidgetMarqueeGroup(messages, startedAt: origin, pointsPerSecond: 40, viewportWidth: 300)
            let timeline = group.timeline(from: origin)
            XCTAssertEqual(timeline.policy, .never)
            XCTAssertEqual(timeline.entries.map(\.date), [origin])
            XCTAssertEqual(timeline.entries.first?.rows.map(\.text), messages)
            XCTAssertTrue(timeline.entries[0].rows.allSatisfy { $0.nextDate == nil })
        }
    }
}

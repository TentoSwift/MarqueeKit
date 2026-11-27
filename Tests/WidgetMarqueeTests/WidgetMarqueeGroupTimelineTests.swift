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
                    let longProgress = long.position(at: hold, copy: 0) - Double(lap % 3)
                    XCTAssertGreaterThan(longProgress, 0)
                    XCTAssertLessThan(longProgress, 1)
                    let restart = start.addingTimeInterval(cycle)
                    for schedule in [short, long] {
                        let head = Double((lap + 1) % 3)
                        XCTAssertEqual(schedule.position(at: start.addingTimeInterval(8.5), copy: 0), head, accuracy: 1e-10)
                        XCTAssertEqual(schedule.position(at: restart, copy: 0), head, accuracy: 1e-10)
                        let next = schedule.position(at: restart.addingTimeInterval(0.5), copy: 0)
                        let first = schedule.position(at: origin.addingTimeInterval(0.5), copy: 0)
                        XCTAssertGreaterThan(first, 0)
                        XCTAssertEqual(next, head + first, accuracy: 1e-10)
                    }
                }
                XCTAssertEqual(short.position(at: origin.addingTimeInterval(-20), copy: 0), 0)
                XCTAssertEqual(rows[2].schedule.position(at: origin.addingTimeInterval(2), copy: 0), 0)
            }
        }
    }

    @MainActor
    func testLongerRowsCruiseThroughShorterArrivalsAcrossLaps() throws {
        let texts = [20, 50, 100].map { String(repeating: "A", count: $0) }
        let speed: CGFloat = 45
        let group = WidgetMarqueeGroup(texts, startedAt: origin, pointsPerSecond: speed,
                                       timing: .easeInOut, pauseBetweenLoops: 1.5, viewportWidth: 10)
        let schedules = WidgetMarqueeGroupEntry(group, date: origin).rows.map(\.schedule)
        let widths = texts.map { WidgetMarqueeMetrics.repeatWidth(for: $0) }
        let models = try group.rows.map { try XCTUnwrap($0.widgetMotion) }
        let timeline = group.timeline(from: origin)
        let travel = models.map(\.duration)
        let cruise = speed * models[0].cruiseFactor

        for lap in 0...2 {
            let start = origin.addingTimeInterval(Double(lap) * schedules[0].cycleDuration)
            func points(_ i: Int, _ elapsed: Double) -> Double {
                let lane = schedules[i].position(at: start.addingTimeInterval(elapsed), copy: 0)
                return (lane - Double(lap) + 3).truncatingRemainder(dividingBy: 3) * widths[i]
            }

            for elapsed in [models[0].accelerationDuration / 2, travel[0] / 2] {
                for i in 1..<models.count { XCTAssertEqual(points(0, elapsed), points(i, elapsed), accuracy: 1e-8) }
            }
            for (i, stop) in travel.enumerated() {
                let arrival = start.addingTimeInterval(stop)
                XCTAssertTrue(timeline.entries.contains { $0.date == arrival })
                XCTAssertEqual(schedules[i].speedFactor(at: arrival, pass: stop), 0, accuracy: 1e-10)
                XCTAssertEqual(points(i, stop + 0.1), widths[i], accuracy: 1e-8)
                // The arriving row is already slowing. The rows with farther to
                // travel cover equal distances either side of its stop.
                let delta = models[i].decelerationDuration / 2
                XCTAssertLessThan((points(i, stop) - points(i, stop - delta)) / delta, cruise * 0.5)
                for j in (i + 1)..<travel.count {
                    XCTAssertEqual((points(j, stop) - points(j, stop - delta)) / delta, cruise, accuracy: 1e-8)
                    XCTAssertEqual((points(j, stop + delta) - points(j, stop)) / delta, cruise, accuracy: 1e-8)
                }
            }
        }
    }

    @MainActor
    func testWidgetKeepsTheCruisingLineLinearThroughAnotherRowsStop() throws {
        let text = "京都発 🚄 東京行き"
        let width = WidgetMarqueeMetrics.repeatWidth(for: text)
        let group = WidgetMarqueeGroup(items: [.init(text, pointsPerSecond: width / 4), .init(text)],
                                       startedAt: origin, pointsPerSecond: width / 8, timing: .easeInOut)
        let schedules = WidgetMarqueeGroupEntry(group, date: origin).rows.map(\.schedule)
        let shortStop = origin.addingTimeInterval(4)
        let approach = shortStop.addingTimeInterval(-0.25)
        let after = shortStop.addingTimeInterval(0.25)
        XCTAssertNotNil(schedules[0].entryAnimation(from: approach, to: shortStop))
        XCTAssertNil(schedules[0].entryAnimation(from: shortStop, to: after))
        XCTAssertEqual(schedules[1].entryAnimation(from: approach, to: shortStop), .linear(duration: 0.25))
        XCTAssertEqual(schedules[1].entryAnimation(from: shortStop, to: after), .linear(duration: 0.25))
        for (row, schedule) in zip(group.rows, schedules) {
            let motion = try XCTUnwrap(row.widgetMotion)
            let dates = schedule.timeline(from: origin) { WidgetMarqueeEntry(text, date: $0, schedule: schedule) }
                .entries.map(\.date)
            for time in [motion.accelerationDuration, motion.decelerationStart, motion.duration] {
                XCTAssertTrue(dates.contains(origin.addingTimeInterval(time)))
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

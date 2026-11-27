import Foundation
import WidgetKit
import XCTest
@testable import MarqueeKit

final class WidgetMarqueeScheduleTests: XCTestCase {
    private struct ReplyEntry: TimelineEntry {
        let date: Date
        let reply: String
    }

    private let schedule = WidgetMarqueeSchedule()

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func testPhaseChangesAtTheStepBoundaryAndWrapsAtMidnight() {
        XCTAssertEqual(schedule.secondsPerStep, 2)
        XCTAssertEqual(schedule.stepsPerPass, 12)

        let cases: [(TimeInterval, Int)] = [
            (-24, 0), (-0.125, 11), (0, 0), (1.875, 0), (2, 1),
            (23.875, 11), (24, 0), (86_399.875, 11), (86_400, 0),
        ]
        for (seconds, expectedPhase) in cases {
            XCTAssertEqual(schedule.phase(at: date(seconds)), expectedPhase, "t = \(seconds)")
        }
    }

    func testTimelineDeliversCustomEntriesAndRequestsReloadBeforeTheLastEntry() {
        let timeline = schedule.timeline(from: date(21.75)) { date in
            ReplyEntry(date: date, reply: "返信の続き")
        }

        let expectedDates = (0...150).map { date(20 + 2 * Double($0)) }
        XCTAssertEqual(timeline.entries.map(\.date), expectedDates)
        XCTAssertTrue(timeline.entries.allSatisfy { $0.reply == "返信の続き" })
        XCTAssertEqual(timeline.policy, .after(date(260)))
    }

    func testLongerPassKeepsTwoSecondSteps() {
        let slow = WidgetMarqueeSchedule(stepsPerPass: 30)
        XCTAssertEqual(slow.secondsPerStep, 2)
        XCTAssertEqual(slow.phase(at: date(-2)), 29)
        XCTAssertEqual(slow.phase(at: date(58)), 29)
        XCTAssertEqual(slow.phase(at: date(60)), 0)
    }

    func testDelayedReloadKeepsTheSameDatesAndPhasesAcrossTheOverlap() {
        let makeEntry = { (date: Date) in ReplyEntry(date: date, reply: "") }
        let original = schedule.timeline(from: date(5.75), entry: makeEntry)
        let reloaded = schedule.timeline(from: date(249.375), entry: makeEntry)

        // The original batch covers 4...304 s. The late reload starts at 248 s.
        let originalTail = original.entries.map(\.date).filter { $0.timeIntervalSinceReferenceDate >= 248 }
        let newHead = reloaded.entries.map(\.date).filter { $0.timeIntervalSinceReferenceDate <= 304 }
        XCTAssertEqual(originalTail.count, 29)
        XCTAssertEqual(newHead, originalTail)
        XCTAssertEqual(newHead.map { schedule.phase(at: $0) }, (4..<33).map { $0 % 12 })
    }

    func testOnlyOneCopyWrapsAtEachPassBoundary() {
        func lanes(at seconds: TimeInterval) -> [Int] {
            (0..<3).map { schedule.lane(at: date(seconds), copy: $0) }
        }
        XCTAssertEqual(lanes(at: -0.125), [35, 11, 23])
        XCTAssertEqual(lanes(at: 0), [0, 12, 24])
        XCTAssertEqual(lanes(at: 24), [12, 24, 0])
        XCTAssertEqual(lanes(at: 48), [24, 0, 12])
        XCTAssertEqual(lanes(at: 72), [0, 12, 24])
    }
}

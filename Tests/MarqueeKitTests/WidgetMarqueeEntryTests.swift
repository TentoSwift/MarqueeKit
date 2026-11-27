import Foundation
import WidgetKit
import XCTest
import MarqueeKit

final class WidgetMarqueeEntryTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 21.75)

    func testEntryAndTimelinePreserveVerbatimInputAndEntryDates() {
        let inputs = ["  京都 👩🏽‍🚀\nCafe\u{301} طوكيو\t ", "\n \t", ""]
        let expectedDates = (0...150).map { Date(timeIntervalSinceReferenceDate: 20 + Double(2 * $0)) }

        for text in inputs {
            let entry = WidgetMarqueeEntry(text, date: start)
            XCTAssertEqual(entry.date, start)
            XCTAssertTrue(entry.text.utf8.elementsEqual(text.utf8))

            let timeline = WidgetMarquee.timeline(for: text, from: start)
            XCTAssertEqual(timeline.entries.map(\.date), expectedDates)
            XCTAssertTrue(timeline.entries.allSatisfy { $0.text.utf8.elementsEqual(text.utf8) })
        }
    }

    func testAutomaticScheduleForLongTextIsSharedByDirectAndScheduledEntries() {
        let text = String(repeating: "桜と朝の空", count: 100)
        let entry = WidgetMarqueeEntry(text, date: start)
        let timeline = WidgetMarquee.timeline(for: text, from: start)

        XCTAssertGreaterThan(entry.schedule.stepsPerPass, WidgetMarqueeSchedule().stepsPerPass)
        XCTAssertFalse(timeline.entries.isEmpty)
        XCTAssertTrue(timeline.entries.allSatisfy { $0.schedule.stepsPerPass == entry.schedule.stepsPerPass })
    }

    func testExplicitScheduleOverridesAutomaticScheduleForLongText() {
        let text = String(repeating: "旅", count: 480)
        let custom = WidgetMarqueeSchedule(stepsPerPass: 7)
        let entry = WidgetMarqueeEntry(text, date: start, schedule: custom)
        let timeline = WidgetMarquee.timeline(for: text, from: start, schedule: custom)

        XCTAssertEqual(entry.schedule.stepsPerPass, 7)
        XCTAssertFalse(timeline.entries.isEmpty)
        XCTAssertTrue(timeline.entries.allSatisfy { $0.schedule.stepsPerPass == 7 })
    }

    func testTextOnlyCallsUseCurrentTimeAndDefaultShortTextSchedule() throws {
        let before = Date.now.timeIntervalSinceReferenceDate
        let entry = WidgetMarqueeEntry("夕焼け")
        let timeline = WidgetMarquee.timeline(for: "夕焼け")
        let after = Date.now.timeIntervalSinceReferenceDate

        XCTAssertGreaterThanOrEqual(entry.date.timeIntervalSinceReferenceDate, before)
        XCTAssertLessThanOrEqual(entry.date.timeIntervalSinceReferenceDate, after)
        XCTAssertEqual(entry.schedule.stepsPerPass, WidgetMarqueeSchedule().stepsPerPass)
        let first = try XCTUnwrap(timeline.entries.first)
        XCTAssertEqual(first.text, entry.text)
        XCTAssertEqual(first.schedule.stepsPerPass, entry.schedule.stepsPerPass)
        // The first timeline entry may precede the request by one scheduling interval.
        XCTAssertGreaterThanOrEqual(first.date.timeIntervalSinceReferenceDate, before - entry.schedule.secondsPerStep)
        XCTAssertLessThanOrEqual(first.date.timeIntervalSinceReferenceDate, after)
    }
}

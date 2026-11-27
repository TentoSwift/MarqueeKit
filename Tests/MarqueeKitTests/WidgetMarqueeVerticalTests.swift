import WidgetKit
import XCTest
@testable import MarqueeKit

final class WidgetMarqueeVerticalTests: XCTestCase {
    func testUprightColumnMeasuresExtendedGraphemesAndNewlinesAsSingleCells() throws {
        let text = "🇯🇵e\u{301}\n👩🏽‍🚀"
        let line = WidgetMarqueeMetrics.line(from: text)
        XCTAssertEqual(Array(line), ["🇯🇵", "e\u{301}", " ", "👩🏽‍🚀"])
        XCTAssertEqual(WidgetMarqueeMetrics.contentLength(for: line, axis: .vertical), 80)
        let schedule = WidgetMarqueeSchedule(for: text, pointsPerSecond: 20, axis: .vertical)
        XCTAssertEqual(try XCTUnwrap(schedule.passDuration), (80 + 28) / 20.0, accuracy: 0.0001)
        XCTAssertEqual(WidgetMarqueeSchedule(for: text).axis, .horizontal)
    }

    func testGroupUsesAvailableHeightAndPreservesAxisInEveryWidgetEntry() throws {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let group = WidgetMarqueeGroup(["🇯🇵東", "東西南北", "東西南北上下"], startedAt: start,
                                       pointsPerSecond: 20, timing: .easeInOut, pauseBetweenLoops: 2,
                                       axis: .vertical, viewportLength: 40)
        XCTAssertEqual(group.rows.map(\.axis), [.vertical, .vertical, .vertical])
        XCTAssertEqual(group.rows.map(\.widgetTravelDuration), [0, 5.4, 7.4])
        XCTAssertEqual(group.rows.map(\.liveTravelDuration), [0, 5.4, 7.4])
        XCTAssertTrue(group.rows.allSatisfy { $0.widgetCycleDuration == 9.4 && $0.liveCycleDuration == 9.4 })
        let short = try XCTUnwrap(group.rows[1].widgetMotion)
        let long = try XCTUnwrap(group.rows[2].widgetMotion)
        XCTAssertEqual(short.progress(at: 5.5), 1)
        XCTAssertGreaterThan(long.speedFactor(at: 5.5), 0)
        XCTAssertTrue(group.timeline(from: start).entries.flatMap(\.rows).allSatisfy { $0.schedule.axis == .vertical })
    }

    func testSingleWidgetTimelineAndSnapshotUseTheSameVerticalSchedule() throws {
        let text = "ABC"
        let entry = WidgetMarqueeEntry(text, pointsPerSecond: 40, axis: .vertical)
        let entries = WidgetMarquee.timeline(for: text, pointsPerSecond: 40, axis: .vertical).entries
        XCTAssertEqual(entry.schedule.axis, .vertical)
        XCTAssertEqual(try XCTUnwrap(entry.schedule.passDuration), 2.2, accuracy: 0.0001)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { $0.schedule.axis == .vertical && $0.schedule.passDuration == entry.schedule.passDuration })
    }
}

import XCTest
@testable import WidgetMarquee

final class WidgetMarqueeGroupTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 123.75)

    func testLongestMovingRowSetsTheCycleIncludingOneSharedPause() {
        let group = WidgetMarqueeGroup(items: [
            .init("京都発🚄\n東京行き", pointsPerSecond: 20),
            .init("京都発🚄\n東京行き", pointsPerSecond: 40, timing: .easeInOut),
            .init("東京", pointsPerSecond: 0.01, viewportWidth: 200),
            .init("静止", pointsPerSecond: 0)
        ], startedAt: start, pointsPerSecond: 60, pauseBetweenLoops: 1.5)

        XCTAssertEqual(group.rows.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(group.rows[0].text, "京都発🚄\n東京行き")
        XCTAssertEqual(group.rows[1].timing, .easeInOut)
        for row in group.rows {
            XCTAssertEqual(row.startedAt, start)
            XCTAssertEqual(row.widgetCycleDuration, group.rows[0].widgetTravelDuration + 1.5)
            XCTAssertEqual(row.liveCycleDuration, group.rows[0].liveTravelDuration + 1.5)
        }
        XCTAssertEqual(group.rows[0].liveTravelDuration, 2 * group.rows[1].liveTravelDuration, accuracy: 0.00001)
        XCTAssertEqual(group.rows[2].widgetTravelDuration, 0)
        XCTAssertEqual(group.rows[2].liveTravelDuration, 0)
        XCTAssertEqual(group.rows[3].liveTravelDuration, 0)
    }

    func testEmptyAndStationaryGroupsDoNotScheduleAPause() {
        XCTAssertTrue(WidgetMarqueeGroup([], startedAt: start, pointsPerSecond: 40).rows.isEmpty)
        let group = WidgetMarqueeGroup(["", " ", "OK"], startedAt: start, pointsPerSecond: 40,
                                       pauseBetweenLoops: 10, viewportWidth: 200)
        XCTAssertTrue(group.rows.allSatisfy { $0.liveCycleDuration == 0 && $0.widgetCycleDuration == 0 })
    }

    func testOversizedStationaryLiveActivityMessageDoesNotHoldUpItsSibling() {
        let group = WidgetMarqueeGroup(["visible", String(repeating: "x", count: 4097)], startedAt: start,
                                       pointsPerSecond: 40, pauseBetweenLoops: .infinity)
        XCTAssertEqual(group.rows[1].liveTravelDuration, 0)
        XCTAssertEqual(group.rows[0].liveCycleDuration, group.rows[0].liveTravelDuration)
        XCTAssertGreaterThan(group.rows[1].widgetTravelDuration, group.rows[0].widgetTravelDuration)
    }

    func testOnlyDistinctMovingEasedArrivalsAffectTheSharedCurve() throws {
        let group = WidgetMarqueeGroup(items: [
            .init("First train"), .init("First train"), .init("Last train for Kyoto via Nagoya"),
            .init("Express", timing: .linear), .init("Fits", viewportWidth: 300), .init("Stopped", pointsPerSecond: 0)
        ], startedAt: start, pointsPerSecond: 40, timing: .easeInOut)

        for (durations, profiles) in [(group.rows.map(\.widgetTravelDuration), group.rows.map(\.widgetMotion)),
                                      (group.rows.map(\.liveTravelDuration), group.rows.map(\.liveMotion))] {
            let first = try XCTUnwrap(profiles[0])
            let duplicate = try XCTUnwrap(profiles[1])
            let last = try XCTUnwrap(profiles[2])
            XCTAssertEqual(Array(first.arrivals), [durations[0]])
            XCTAssertEqual(first.arrivals, duplicate.arrivals)
            XCTAssertEqual(Array(last.arrivals), [durations[0], durations[2]])
            XCTAssertTrue(profiles[3...].allSatisfy { $0 == nil })
        }

        let equal = WidgetMarqueeGroup(["First train", "First train"], startedAt: start,
                                       pointsPerSecond: 40, timing: .easeInOut)
        XCTAssertTrue(equal.rows.allSatisfy { $0.liveMotion == nil && $0.widgetMotion == nil })
    }
}

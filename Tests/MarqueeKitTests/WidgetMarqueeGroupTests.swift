import XCTest
@testable import MarqueeKit

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

    func testNearbyArrivalsNeverMakeTheLongerRowSlowThenReaccelerate() throws {
        let text = "Kyoto express"
        let width = WidgetMarqueeMetrics.repeatWidth(for: text)
        let group = WidgetMarqueeGroup(items: [
            .init(text, pointsPerSecond: width / 2),
            .init(text, pointsPerSecond: width / 10),
            .init(text, pointsPerSecond: width / 10.08)
        ], startedAt: start, pointsPerSecond: 40, timing: .easeInOut)
        let motion = try XCTUnwrap(group.rows[2].widgetMotion)
        // Its own terminal ramp overlaps its neighbor's stop at 10 seconds.
        XCTAssertLessThan(motion.decelerationStart, 10)
        XCTAssertGreaterThan(motion.speedFactor(at: 10), 0)
        var previousSpeed = motion.cruiseFactor
        for i in 0...1000 {
            let t = motion.accelerationDuration + (motion.duration - motion.accelerationDuration) * Double(i) / 1000
            let speed = motion.speedFactor(at: t)
            XCTAssertLessThanOrEqual(speed, previousSpeed + 1e-12)
            previousSpeed = speed
        }
        XCTAssertEqual(motion.speedFactor(at: motion.duration), 0)
    }

    func testExtremeTravelRatiosKeepProfilesFiniteAndMonotone() throws {
        let durations = [1e-275, 1, 1e275]
        let profiles = WidgetMarqueeGroup.Motion.profiles(for: durations, timings: [.easeInOut, .easeInOut, .easeInOut])
        for duration in durations {
            let motion = try XCTUnwrap(profiles[duration])
            var previous = 0.0
            for fraction in [0.0, 0.01, 0.75, 0.99, 1.0] {
                let elapsed = fraction * duration
                let position = motion.progress(at: elapsed)
                XCTAssertTrue((previous...1).contains(position))
                XCTAssertTrue(motion.speedFactor(at: elapsed).isFinite)
                previous = position
            }
            XCTAssertEqual(previous, 1)
        }
    }

    func testOnlyMovingEasedRowsSetTheCommonAccelerationAndCruise() throws {
        let group = WidgetMarqueeGroup(items: [
            .init("First train"), .init("First train"), .init("Last train for Kyoto via Nagoya"),
            .init("Express", timing: .linear), .init("Fits", viewportWidth: 300), .init("Stopped", pointsPerSecond: 0)
        ], startedAt: start, pointsPerSecond: 40, timing: .easeInOut)

        for (durations, profiles) in [(group.rows.map(\.widgetTravelDuration), group.rows.map(\.widgetMotion)),
                                      (group.rows.map(\.liveTravelDuration), group.rows.map(\.liveMotion))] {
            let first = try XCTUnwrap(profiles[0])
            let duplicate = try XCTUnwrap(profiles[1])
            let last = try XCTUnwrap(profiles[2])
            XCTAssertEqual(first.duration, durations[0])
            XCTAssertEqual(last.duration, durations[2])
            XCTAssertEqual(first.cruiseFactor, last.cruiseFactor)
            XCTAssertEqual(first.accelerationDuration, last.accelerationDuration)
            XCTAssertEqual(first.decelerationStart, duplicate.decelerationStart)
            XCTAssertEqual(first.accelerationDuration, first.decelerationDuration, accuracy: 1e-12)
            XCTAssertGreaterThan(last.decelerationStart, first.duration)
            XCTAssertTrue(profiles[3...].allSatisfy { $0 == nil })
        }

        let equal = WidgetMarqueeGroup(["First train", "First train"], startedAt: start,
                                       pointsPerSecond: 40, timing: .easeInOut)
        XCTAssertTrue(equal.rows.allSatisfy { $0.liveMotion == nil && $0.widgetMotion == nil })
    }
}

import SwiftUI
import XCTest
@testable import MarqueeKit

final class MarqueeRampsTests: XCTestCase {
    private let ramps = MarqueeRamps(acceleration: .init(duration: 3, curve: .easeIn),
                                     deceleration: .init(duration: 1.5, curve: .easeOut))
    private let origin = Date(timeIntervalSinceReferenceDate: 0)

    func testAsymmetricSpeedCurvesIntegrateToExactlyOnePass() throws {
        let motion = try XCTUnwrap(WidgetMarqueeGroup.Motion.custom(ramps, baseTravel: 10, fixedDuration: false))
        // At 10 pt/s the 100-point pass uses 10 pt to accelerate, 80 pt
        // to cruise and 10 pt to brake. Its average is 8 pt/s.
        XCTAssertEqual(motion.duration, 12.5, accuracy: 1e-12)
        XCTAssertEqual(motion.decelerationStart, 11, accuracy: 1e-12)
        let samples: [(time: Double, distance: Double, speed: Double)] = [
            (0, 0, 0), (1.5, 1.25, 2.5), (3, 10, 10), (5, 30, 10),
            (11, 90, 10), (11.75, 96.875, 7.5), (12.5, 100, 0), (13, 100, 0)
        ]
        for sample in samples {
            XCTAssertEqual(100 * motion.progress(at: sample.time), sample.distance, accuracy: 1e-9)
            XCTAssertEqual(8 * motion.speedFactor(at: sample.time), sample.speed, accuracy: 1e-9)
        }
    }

    func testOversizedRampsFitInProportionAndBothZeroUsesConstantSpeed() throws {
        let large = MarqueeRamps(acceleration: .init(duration: 6), deceleration: .init(duration: 6, curve: .easeIn))
        let shortened = try XCTUnwrap(WidgetMarqueeGroup.Motion.custom(large, baseTravel: 2, fixedDuration: false))
        XCTAssertEqual(shortened.accelerationDuration, 2.4, accuracy: 1e-12)
        XCTAssertEqual(shortened.decelerationDuration, 2.4, accuracy: 1e-12)
        XCTAssertEqual(shortened.duration, 4.8, accuracy: 1e-12)
        XCTAssertEqual(shortened.progress(at: 2.4), 0.6, accuracy: 1e-12)

        let fixed = try XCTUnwrap(WidgetMarqueeGroup.Motion.custom(large, baseTravel: 2, fixedDuration: true))
        XCTAssertEqual(fixed.duration, 2)
        XCTAssertEqual(fixed.accelerationDuration, 1)
        XCTAssertEqual(fixed.decelerationDuration, 1)
        XCTAssertEqual(fixed.progress(at: 1), 0.6, accuracy: 1e-12)

        let instant = MarqueeRamps(acceleration: .init(duration: -.infinity), deceleration: .init(duration: -1))
        let linear = try XCTUnwrap(WidgetMarqueeGroup.Motion.custom(instant, baseTravel: 2, fixedDuration: false))
        XCTAssertEqual(linear.duration, 2)
        XCTAssertEqual(linear.progress(at: 1.5), 0.75)
        XCTAssertEqual(linear.speedFactor(at: 0), 1)
        XCTAssertEqual(linear.speedFactor(at: 2.1), 0)
        let extreme = MarqueeRamps(acceleration: .init(duration: .greatestFiniteMagnitude),
                                   deceleration: .init(duration: .greatestFiniteMagnitude))
        let fitted = try XCTUnwrap(WidgetMarqueeGroup.Motion.custom(extreme, baseTravel: 3, fixedDuration: true))
        XCTAssertEqual(fitted.accelerationDuration, 1.5, accuracy: 1e-12)
        XCTAssertEqual(fitted.progress(at: 1.5), 0.5, accuracy: 1e-12)
    }

    @MainActor
    func testStandaloneTimelinesIncludeRampBoundariesAndPreserveTheDefaultPassTime() throws {
        let entry = WidgetMarqueeEntry("ABCDE", date: origin, pointsPerSecond: 10, axis: .vertical,
                                       repeatSpacing: 0, ramps: ramps)
        XCTAssertEqual(entry.schedule.ramps, ramps)
        _ = WidgetMarquee(entry)
        _ = WidgetMarquee("ABCDE", ramps: ramps)
        let timeline = WidgetMarquee.timeline(for: "ABCDE", from: origin, pointsPerSecond: 10,
                                             axis: .vertical, repeatSpacing: 0, ramps: ramps)
        XCTAssertEqual(entry.schedule.passDuration, 12.5)
        let dates = timeline.entries.map { $0.date.timeIntervalSinceReferenceDate }
        for t in [3, 11, 12.5, 15.5] { XCTAssertTrue(dates.contains(t), "t=\(t)") }
        XCTAssertEqual(WidgetMarqueeSchedule(stepsPerPass: 4, ramps: ramps).passDuration, 8)
        XCTAssertEqual(WidgetMarqueeSchedule(for: "ABCDE", ramps: ramps).passDuration, 24)
    }

    @MainActor
    func testOneInstantEndUsesTheCorrectIncomingSlopeAtTheWrap() throws {
        // A 4-second fixed pass reaches cruising speed after a 2-second
        // launch, then stops immediately at the loop boundary.
        let onlyLaunch = MarqueeRamps(acceleration: .init(duration: 2))
        let schedule = WidgetMarqueeSchedule(stepsPerPass: 2, ramps: onlyLaunch)
        let stop = origin.addingTimeInterval(4)
        let approach = origin.addingTimeInterval(2)
        XCTAssertEqual(schedule.previousSample(before: stop), approach)
        XCTAssertEqual(schedule.entryAnimation(from: approach, to: stop), .linear(duration: 2))

        let onlyBrake = WidgetMarqueeSchedule(stepsPerPass: 2, ramps: .init(deceleration: .init(duration: 2)))
        XCTAssertEqual(onlyBrake.speedFactor(at: stop, pass: 4, arriving: true), 0)
        XCTAssertEqual(onlyBrake.speedFactor(at: stop, pass: 4), 4.0 / 3, accuracy: 1e-10)
    }

    func testGroupUsesTheSameCruiseSpeedAndRestartsAfterIndependentStops() throws {
        let group = WidgetMarqueeGroup(items: [.init("ABCDE"), .init("ABCDEFGHIJ"),
                                               .init("ABCDE", timing: .linear), .init("ABCDE", timing: .linear, ramps: ramps)],
                                       startedAt: origin, pointsPerSecond: 10, pauseBetweenLoops: 2,
                                       axis: .vertical, repeatSpacing: 0, ramps: ramps)
        XCTAssertEqual(group.rows.map(\.ramps), [ramps, ramps, nil, ramps])
        XCTAssertEqual(group.rows.map(\.liveTravelDuration), [12.5, 22.5, 10, 12.5])
        XCTAssertTrue(group.rows.allSatisfy { $0.liveCycleDuration == 24.5 && $0.widgetCycleDuration == 24.5 })
        let first = WidgetMarqueeSchedule(group.rows[0])
        let second = WidgetMarqueeSchedule(group.rows[1])
        func distance(_ schedule: WidgetMarqueeSchedule, length: Double, time: Double) -> Double {
            schedule.position(at: origin.addingTimeInterval(time), copy: 0) * length
        }
        for lengthAndSchedule in [(100.0, first), (200.0, second)] {
            let (length, schedule) = lengthAndSchedule
            XCTAssertEqual(distance(schedule, length: length, time: 5) - distance(schedule, length: length, time: 4),
                           10, accuracy: 1e-9)
            XCTAssertEqual(distance(schedule, length: length, time: 24), length, accuracy: 1e-9)
            XCTAssertEqual(distance(schedule, length: length, time: 26) - length, 1.25, accuracy: 1e-9)
        }
        XCTAssertEqual(distance(second, length: 200, time: 13) - distance(second, length: 200, time: 12), 10, accuracy: 1e-9)
        XCTAssertEqual(distance(first, length: 100, time: 13), 100, accuracy: 1e-9)
    }

    func testCodableRoundTripsWithoutChangingLegacyTimingStrings() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(MarqueeRamps.self, from: encoder.encode(ramps)), ramps)
        XCTAssertEqual(try decoder.decode(WidgetMarqueeTiming.self, from: Data("\"easeInOut\"".utf8)), .easeInOut)
        XCTAssertEqual(String(decoding: try encoder.encode(WidgetMarqueeTiming.linear), as: UTF8.self), "\"linear\"")
        let invalid = Data(#"{"duration":-3,"curve":"easeOut"}"#.utf8)
        XCTAssertEqual(try decoder.decode(MarqueeRamps.Ramp.self, from: invalid), .init(duration: 0, curve: .easeOut))
        XCTAssertEqual(MarqueeRamps.Ramp(duration: .nan).duration, 0)
    }
}

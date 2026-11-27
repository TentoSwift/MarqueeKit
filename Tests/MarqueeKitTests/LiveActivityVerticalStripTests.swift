import XCTest
@testable import MarqueeKit

final class LiveActivityVerticalStripTests: XCTestCase {
    func testLimitsCountGraphemesAndImageTiles() {
        let astronaut = "👩🏽‍🚀"
        XCTAssertTrue(LiveActivityVerticalStrip.supportsAnimation(String(repeating: astronaut, count: 96)))
        XCTAssertFalse(LiveActivityVerticalStrip.supportsAnimation(String(repeating: "東", count: 97)))

        let mixed = String(repeating: "東" + astronaut, count: 12)
        XCTAssertTrue(LiveActivityVerticalStrip.supportsAnimation(mixed))
        XCTAssertFalse(LiveActivityVerticalStrip.supportsAnimation(mixed + "東"))
        XCTAssertNil(LiveActivityVerticalStrip.unit(for: mixed + "東"))
    }

    func testStaticLiveColumnDoesNotHoldMovingSiblingsAtTheHead() {
        let largeMixedLine = String(repeating: "東🚃", count: 520)
        XCTAssertEqual(largeMixedLine.utf8.count, 3_640)
        let group = WidgetMarqueeGroup([largeMixedLine, "東京大阪京都"], startedAt: .distantPast,
                                       pointsPerSecond: 20, timing: .easeInOut, pauseBetweenLoops: 2,
                                       axis: .vertical, viewportLength: 40)
        let fallback = group.rows[0]
        let moving = group.rows[1]
        XCTAssertEqual(fallback.liveTravelDuration, 0)
        XCTAssertEqual(moving.liveTravelDuration, 7.4, accuracy: 0.0001)
        XCTAssertNil(moving.liveMotion)
        XCTAssertEqual(fallback.liveCycleDuration, 9.4, accuracy: 0.0001)
        XCTAssertEqual(moving.liveCycleDuration, 9.4, accuracy: 0.0001)
        XCTAssertGreaterThan(fallback.widgetTravelDuration, moving.widgetTravelDuration)
        XCTAssertEqual(moving.widgetCycleDuration, fallback.widgetTravelDuration + 2, accuracy: 0.0001)
    }
}

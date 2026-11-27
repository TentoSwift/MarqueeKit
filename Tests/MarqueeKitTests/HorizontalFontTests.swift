import UIKit
import XCTest
@testable import MarqueeKit

final class HorizontalFontTests: XCTestCase {
    func testEachHorizontalRowUsesItsOwnFontForFitAndTravel() throws {
        let text = "iiiiiiiiiiii"
        let regular = UIFont.systemFont(ofSize: 18)
        let monospace = UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        let regularWidth = (text as NSString).size(withAttributes: [.font: regular]).width
        let monospaceWidth = (text as NSString).size(withAttributes: [.font: monospace]).width
        let viewport = (regularWidth + monospaceWidth) / 2
        XCTAssertLessThan(ceil(regularWidth), viewport)
        XCTAssertGreaterThan(ceil(monospaceWidth), viewport)

        let group = WidgetMarqueeGroup(items: [
            .init(text, viewportWidth: viewport, horizontalFont: regular),
            .init(text, viewportWidth: viewport, horizontalFont: monospace)
        ], startedAt: .distantPast, pointsPerSecond: 30, pauseBetweenLoops: 2)
        let stationary = group.rows[0], moving = group.rows[1]
        XCTAssertEqual(stationary.liveTravelDuration, 0)
        XCTAssertEqual(stationary.widgetTravelDuration, 0)
        let livePeriod = ((text + "    ") as NSString).size(withAttributes: [.font: monospace]).width
        XCTAssertEqual(moving.liveTravelDuration, livePeriod / 30, accuracy: 0.00001)
        XCTAssertEqual(moving.widgetTravelDuration, (ceil(monospaceWidth) + 28) / 30, accuracy: 0.00001)
        XCTAssertEqual(stationary.liveCycleDuration, moving.liveTravelDuration + 2, accuracy: 0.00001)

        let entry = try XCTUnwrap(group.timeline().entries.first)
        XCTAssertEqual(entry.rows.map(\.schedule.horizontalFont), [regular, monospace])
    }

    func testStandaloneEntryUsesTheSelectedFontAndPreservesTheVerticalCellSize() throws {
        let font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        let text = "夜明け — Platform"
        let entry = WidgetMarqueeEntry(text, pointsPerSecond: 40, horizontalFont: font)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        XCTAssertEqual(try XCTUnwrap(entry.schedule.passDuration), (ceil(width) + 28) / 40, accuracy: 0.00001)
        XCTAssertEqual(entry.schedule.horizontalFont, font)
        XCTAssertNil(WidgetMarqueeEntry(text).schedule.horizontalFont)

        let vertical = WidgetMarqueeGroup([text], startedAt: .now, pointsPerSecond: 40,
                                          axis: .vertical, horizontalFont: font)
        let original = WidgetMarqueeGroup([text], startedAt: .now, pointsPerSecond: 40, axis: .vertical)
        XCTAssertEqual(vertical.rows[0].liveTravelDuration, original.rows[0].liveTravelDuration)
        XCTAssertEqual(vertical.rows[0].widgetTravelDuration, original.rows[0].widgetTravelDuration)
    }
}

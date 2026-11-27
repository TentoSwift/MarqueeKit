import SwiftUI
import UIKit
import XCTest
@testable import MarqueeKit

final class WidgetRepeatSpacingTests: XCTestCase {
    func testScheduleAndTimelineUseTheSpecifiedSpacingInPoints() throws {
        let text = "京都から🚄東京"
        let font = UIFont.systemFont(ofSize: 19)
        let speed: CGFloat = 30
        let inputs: [(CGFloat?, CGFloat)] = [(nil, 28), (.nan, 28), (.infinity, 28), (-4, 0), (0, 0), (14.25, 14.25)]
        for axis in [MarqueeAxis.horizontal, .vertical] {
            let length = axis == .vertical ? CGFloat(text.count) * 20 : ceil((text as NSString).size(withAttributes: [.font: font]).width)
            for (input, expected) in inputs {
                let entry = WidgetMarqueeEntry(text, pointsPerSecond: speed, axis: axis, horizontalFont: font,
                                               repeatSpacing: input)
                let duration = try XCTUnwrap(entry.schedule.passDuration)
                XCTAssertEqual(entry.schedule.repeatSpacing, expected)
                XCTAssertEqual(duration, (length + expected) / speed, accuracy: 1e-9)
                let timeline = WidgetMarquee.timeline(for: text, pointsPerSecond: speed, axis: axis,
                                                      horizontalFont: font, repeatSpacing: input)
                XCTAssertTrue(timeline.entries.allSatisfy {
                    $0.schedule.repeatSpacing == expected && $0.schedule.passDuration == duration
                })
            }
        }
        let stepped = WidgetMarqueeSchedule(stepsPerPass: 8, repeatSpacing: 1.25)
        XCTAssertEqual(stepped.repeatSpacing, 1.25)
        XCTAssertEqual(stepped.cycleDuration, 16)
        XCTAssertEqual(WidgetMarqueeSchedule(for: text, repeatSpacing: 3.5).repeatSpacing, 3.5)
    }

    func testGroupSpacingOverridesChangeTravelAndPreserveTheCommonRestart() throws {
        let text = "Express"
        let font = UIFont.systemFont(ofSize: 17)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        let legacyWidth = ((text + "    ") as NSString).size(withAttributes: [.font: font]).width
        let horizontal = WidgetMarqueeGroup([text], startedAt: .now, pointsPerSecond: 40, repeatSpacing: 7)
        XCTAssertEqual(horizontal.rows.first?.repeatSpacing, 7)
        for axis in [MarqueeAxis.horizontal, .vertical] {
            let group = WidgetMarqueeGroup(items: [
                .init(text, horizontalFont: font),
                .init(text, horizontalFont: font, repeatSpacing: -2),
                .init(text, horizontalFont: font, repeatSpacing: 48.75),
                .init(text, horizontalFont: font, repeatSpacing: .infinity),
                .init(text, viewportLength: 300, horizontalFont: font, repeatSpacing: 500),
            ], startedAt: .now, pointsPerSecond: 40, pauseBetweenLoops: 2, axis: axis, repeatSpacing: 13.25)
            let rowSpacing: [CGFloat?] = [13.25, 0, 48.75, nil, 500]
            XCTAssertEqual(group.rows.map(\.repeatSpacing), rowSpacing)
            for (index, widgetSpacing) in [13.25, 0, 48.75, 28].enumerated() {
                let row = group.rows[index]
                let widgetLength = axis == .vertical ? CGFloat(text.count) * 20 : ceil(width)
                let livePeriod = axis == .vertical ? widgetLength + widgetSpacing : rowSpacing[index].map { width + $0 } ?? legacyWidth
                XCTAssertEqual(row.widgetTravelDuration, (widgetLength + widgetSpacing) / 40, accuracy: 1e-9)
                XCTAssertEqual(row.liveTravelDuration, livePeriod / 40, accuracy: 1e-9)
                XCTAssertEqual(row.widgetCycleDuration, group.rows[2].widgetTravelDuration + 2)
                XCTAssertEqual(row.liveCycleDuration, group.rows[2].liveTravelDuration + 2)
            }
            XCTAssertEqual(group.rows[4].widgetTravelDuration, 0)
            XCTAssertEqual(group.rows[4].liveTravelDuration, 0)
            let entry = try XCTUnwrap(group.timeline().entries.first)
            XCTAssertEqual(entry.rows.map(\.schedule.repeatSpacing), [13.25, 0, 48.75, 28, 500])
        }
    }

    @MainActor
    func testBothAxesRenderTheRequestedGapAtTheWrap() throws {
        let text = String(repeating: "W", count: 15)
        for axis in [MarqueeAxis.horizontal, .vertical] {
            let length = WidgetMarqueeMetrics.contentLength(for: text, axis: axis)
            // The tail has moved 15 points beyond the leading edge. A wide
            // gap now fills the viewport; a zero gap already shows the next copy.
            let date = Date(timeIntervalSinceReferenceDate: (length + 15) / 20)
            func brightestPixel(spacing: CGFloat) throws -> UInt8 {
                let view = WidgetMarquee(text, date: date, pointsPerSecond: 20, axis: axis, repeatSpacing: spacing)
                    .frame(width: axis == .horizontal ? 40 : 23, height: axis == .horizontal ? 22 : 40)
                    .foregroundStyle(.white)
                    .background(.black)
                let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
                var bytes = [UInt8](repeating: 0, count: image.width * image.height)
                return try bytes.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                                          bitsPerComponent: 8, bytesPerRow: image.width,
                                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    return buffer.max() ?? 0
                }
            }
            XCTAssertGreaterThan(try brightestPixel(spacing: 0), 100)
            XCTAssertEqual(try brightestPixel(spacing: 96.5), 0)
        }
    }
}

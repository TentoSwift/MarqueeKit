import CoreText
import SwiftUI
import UIKit
import XCTest
@testable import MarqueeKit

final class LiveRepeatSpacingTests: XCTestCase {
    private let spacings: [CGFloat] = [0, 0.5, 24.5, 64]

    @MainActor
    func testHorizontalSpacerAddsTheRequestedRenderedWidth() throws {
        try registerSpacingFont()
        let letter = Text(verbatim: "I").font(.system(size: 16, design: .monospaced))
        let control = try renderedWidth(of: Text("\(letter)\(letter)"))
        for spacing in spacings {
            let spacer = LiveActivityMarquee.spacer(spacing)
            let width = try renderedWidth(of: Text("\(letter)\(spacer)\(letter)"))
            XCTAssertEqual(width - control, spacing, accuracy: 0.25, "Spacing \(spacing)")
        }
    }

    @MainActor
    func testVerticalStripAddsTheRequestedAdvanceBeforeRotation() throws {
        try registerSpacingFont()
        let line = "東京"
        let cells = CGFloat(line.count) * WidgetMarqueeMetrics.verticalAdvance
        for spacing in spacings {
            let strip = try XCTUnwrap(LiveActivityVerticalStrip.unit(for: line, repeatSpacing: spacing))
            let advance = try renderedWidth(of: strip)
            XCTAssertEqual(advance - cells, spacing, accuracy: 0.25, "Spacing \(spacing)")
        }

        let defaultStrip = try XCTUnwrap(LiveActivityVerticalStrip.unit(for: line))
        XCTAssertEqual(try renderedWidth(of: defaultStrip) - cells, WidgetMarqueeMetrics.gap, accuracy: 0.25)
    }

    @MainActor
    private func renderedWidth(of text: Text) throws -> CGFloat {
        let renderer = ImageRenderer(content: text.fixedSize().environment(\.displayScale, 2))
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage).size.width
    }

    @MainActor
    private func registerSpacingFont() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "MarqueeRepeatSpace", withExtension: "ttf"))
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        _ = try XCTUnwrap(UIFont(name: "MarqueeRepeatSpace-Regular", size: 14))
    }
}

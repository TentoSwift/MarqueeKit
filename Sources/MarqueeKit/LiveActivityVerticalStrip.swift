import SwiftUI
import UIKit

/// Inline text attachments let WidgetKit move the whole strip with its native clock.
/// The enclosing view rotates clockwise; each glyph here gets the opposite rotation.
enum LiveActivityVerticalStrip {
    private struct Tile {
        let cells: Substring
        let count: Int
        let colorEmoji: Bool
    }

    /// Both the view and the group's clock must agree when a row becomes stationary.
    static func supportsAnimation(_ line: String) -> Bool { tiles(for: line) != nil }

    /// Bound the image data and attachment count before drawing anything. A long mixed
    /// string can fit in ActivityKit's content state but make WidgetKit reject the archive.
    private static func tiles(for line: String) -> [Tile]? {
        var result = [Tile]()
        var start = line.startIndex
        var total = 0
        while start < line.endIndex {
            guard result.count < 24 else { return nil }
            let colorEmoji = usesColorEmoji(line[start])
            var end = start
            var count = 0
            repeat {
                end = line.index(after: end)
                count += 1
                total += 1
                guard total <= 96 else { return nil }
            } while end < line.endIndex && count < 64 && usesColorEmoji(line[end]) == colorEmoji
            result.append(Tile(cells: line[start..<end], count: count, colorEmoji: colorEmoji))
            start = end
        }
        return result
    }

    static func unit(for line: String, repeatSpacing: CGFloat? = nil) -> Text? {
        guard let tiles = tiles(for: line) else { return nil }
        let advance = WidgetMarqueeMetrics.verticalAdvance
        let thickness = WidgetMarqueeMetrics.columnWidth
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.preferredRange = .standard
        // At either scale the combined tiles (including the gap) use fewer than 48k pixels.
        format.scale = line.count <= 24 ? 2 : 1
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WidgetMarqueeMetrics.font, .foregroundColor: UIColor.white
        ]
        var chunks = [Text]()
        for (index, tile) in tiles.enumerated() {
            let gap = index == tiles.count - 1 && repeatSpacing == nil ? WidgetMarqueeMetrics.gap : 0
            let size = CGSize(width: CGFloat(tile.count) * advance + gap, height: thickness)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let context = renderer.cgContext
                for (index, character) in tile.cells.enumerated() {
                    let glyph = String(character) as NSString
                    let bounds = glyph.size(withAttributes: attributes)
                    context.saveGState()
                    context.translateBy(x: (CGFloat(index) + 0.5) * advance, y: thickness / 2)
                    context.rotate(by: -.pi / 2)
                    glyph.draw(at: CGPoint(x: -bounds.width / 2, y: -bounds.height / 2), withAttributes: attributes)
                    context.restoreGState()
                }
            }
            // Tint text with the caller's foreground style and preserve native emoji colors.
            chunks.append(Text(Image(uiImage: image).renderingMode(tile.colorEmoji ? .original : .template)))
        }
        if let repeatSpacing { chunks.append(LiveActivityMarquee.spacer(repeatSpacing)) }
        return LiveActivityMarquee.joined(chunks)
    }

    private static func usesColorEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        return !scalars.contains("\u{FE0E}") && (scalars.contains("\u{FE0F}") || scalars.contains { $0.properties.isEmojiPresentation })
    }

    static func stationary(_ text: String, viewport: CGFloat) -> some View {
        // Only the cells that may be visible need to be archived for static presentations.
        let count = Int(min(CGFloat(text.count), max(0, ceil(viewport / WidgetMarqueeMetrics.verticalAdvance))))
        let characters = Array(text.prefix(count))
        return VStack(spacing: 0) {
            ForEach(characters.indices, id: \.self) { index in
                Text(verbatim: String(characters[index]))
                    .font(Font(WidgetMarqueeMetrics.font))
                    .lineLimit(1)
                    .frame(width: WidgetMarqueeMetrics.columnWidth, height: WidgetMarqueeMetrics.verticalAdvance)
            }
        }
        .fixedSize()
        .frame(height: viewport, alignment: .top)
        .clipped()
    }
}

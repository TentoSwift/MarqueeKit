import SwiftUI
import UIKit

/// A one-line, leftward marquee driven by the dates of WidgetKit timeline entries.
///
/// Give the view the entry's date and construct the timeline with the same
/// schedule. At normal motion settings, text that overflows the available width
/// moves to its next position on an entry update. VoiceOver reads the text once.
public struct WidgetMarquee: View {
    private let text: String
    private let date: Date
    private let schedule: WidgetMarqueeSchedule

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reducedLuminance

    private static let typeface = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let gap: CGFloat = 28

    /// Creates a marquee for the entry displayed at `date`.
    ///
    /// The text stays stationary when it fits the available width, Reduce Motion
    /// is enabled, or the system displays the widget with reduced luminance.
    public init(_ text: String, date: Date, schedule: WidgetMarqueeSchedule = .init()) {
        self.text = text
        self.date = date
        self.schedule = schedule
    }

    public var body: some View {
        let line = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
        let textWidth = ceil((line as NSString).size(withAttributes: [.font: Self.typeface]).width)
        let label = Text(verbatim: line).font(Font(Self.typeface)).lineLimit(1)

        GeometryReader { viewport in
            if textWidth <= viewport.size.width || reduceMotion || reducedLuminance {
                label.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ZStack(alignment: .leading) {
                    ForEach(0..<3, id: \.self) { copy in
                        let lane = schedule.lane(at: date, copy: copy)
                        let shift = (textWidth + Self.gap) * (1 - CGFloat(lane) / CGFloat(schedule.stepsPerPass))
                        label
                            .fixedSize()
                            .offset(x: shift)
                            .animation(lane == 0 ? nil : .linear(duration: schedule.secondsPerStep), value: lane)
                            // A returning copy may skip the offscreen reset entry.
                            // A new identity keeps it from animating backwards across the line.
                            .id(schedule.copyCycle(at: date, copy: copy))
                            .transition(.identity)
                    }
                }
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .leading)
                .clipped()
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

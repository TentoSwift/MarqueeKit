import Foundation
import WidgetKit

/// The text and scroll position to display at a particular point in a widget's timeline.
public struct WidgetMarqueeEntry: TimelineEntry, Sendable {
    /// The complete text supplied by the caller.
    public let text: String
    /// The date WidgetKit uses to present this entry.
    public let date: Date
    /// The schedule used to derive the scroll position from the date.
    public let schedule: WidgetMarqueeSchedule

    /// Creates a single entry, for example for a placeholder or snapshot.
    ///
    /// Omitting the schedule chooses the number of positions based on the length of the text.
    public init(_ text: String, date: Date = .now, schedule: WidgetMarqueeSchedule? = nil) {
        self.text = text
        self.date = date
        self.schedule = schedule ?? WidgetMarqueeSchedule(for: text)
    }
}

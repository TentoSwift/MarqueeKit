import UIKit
import WidgetKit

/// The text and scroll position to display at a particular point in a widget's timeline.
public struct WidgetMarqueeEntry: TimelineEntry, Sendable {
    /// The complete text supplied by the caller.
    public let text: String
    /// The date WidgetKit uses to present this entry.
    public let date: Date
    /// The schedule used to derive the scroll position from the date.
    public let schedule: WidgetMarqueeSchedule

    // Generated timelines target this upcoming position during the current entry.
    let nextDate: Date?

    init(_ text: String, date: Date, schedule: WidgetMarqueeSchedule, nextDate: Date?) {
        self.text = text
        self.date = date
        self.schedule = schedule
        self.nextDate = nextDate
    }

    /// Creates a single entry, for example for a placeholder or snapshot.
    ///
    /// Omitting the schedule chooses the number of positions based on the length of the text.
    public init(_ text: String, date: Date = .now, schedule: WidgetMarqueeSchedule? = nil) {
        self.init(text, date: date, schedule: schedule ?? WidgetMarqueeSchedule(for: text), nextDate: nil)
    }

    /// Creates an entry with the supplied travel speed, timing, and loop pause.
    public init(
        _ text: String, date: Date = .now, pointsPerSecond: CGFloat? = nil,
        timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
        axis: MarqueeAxis = .horizontal, horizontalFont: UIFont? = nil
    ) {
        let schedule = WidgetMarqueeSchedule(
            for: text, pointsPerSecond: pointsPerSecond, timing: timing, pauseBetweenLoops: pauseBetweenLoops,
            axis: axis, horizontalFont: horizontalFont
        )
        self.init(text, date: date, schedule: schedule)
    }
}

/// One WidgetKit entry containing all rows of a synchronized marquee group, in input order.
public struct WidgetMarqueeGroupEntry: TimelineEntry, Sendable {
    public let date: Date
    public let rows: [WidgetMarqueeEntry]

    /// Creates a placeholder or snapshot for the group at the supplied date.
    public init(_ group: WidgetMarqueeGroup, date: Date = .now) {
        self.date = date
        self.rows = group.rows.map { WidgetMarqueeEntry($0.text, date: date, schedule: WidgetMarqueeSchedule($0)) }
    }

    fileprivate init(date: Date, rows: [WidgetMarqueeEntry]) {
        self.date = date
        self.rows = rows
    }
}

extension WidgetMarqueeGroup {
    /// Builds one timeline for the widget. All rows receive the same entry dates,
    /// including when a moving member finishes and when the whole group restarts.
    public func timeline(from date: Date = .now) -> Timeline<WidgetMarqueeGroupEntry> {
        let schedules = rows.map(WidgetMarqueeSchedule.init)
        return WidgetMarqueeSchedule.timeline(for: schedules, from: date) { date, next in
            let entries = zip(rows, schedules).map { row, schedule in
                WidgetMarqueeEntry(row.text, date: date, schedule: schedule,
                                   nextDate: schedule.passDuration == 0 ? nil : next)
            }
            return WidgetMarqueeGroupEntry(date: date, rows: entries)
        }
    }
}

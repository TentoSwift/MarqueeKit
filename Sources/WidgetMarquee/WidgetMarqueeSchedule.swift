import Foundation
import WidgetKit

/// Schedules the positions of a marquee on an absolute, two-second grid.
///
/// The default 12-step pass takes 24 seconds when WidgetKit presents each entry.
/// WidgetKit may combine or skip entries and may delay a requested reload.
public struct WidgetMarqueeSchedule: Sendable {
    /// Time between successive scheduled positions, in seconds.
    public let secondsPerStep: TimeInterval = 2

    /// Number of scheduled positions in one pass through the text.
    public let stepsPerPass: Int

    /// Creates a two-second schedule with the specified number of positions per pass.
    ///
    /// More positions reduce the distance between entries for long text. Supported
    /// values are 2 through 3,600 (a scheduled pass of four seconds to two hours).
    public init(stepsPerPass: Int = 12) {
        precondition((2...3_600).contains(stepsPerPass), "stepsPerPass must be between 2 and 3,600")
        self.stepsPerPass = stepsPerPass
    }

    /// Returns the zero-based position within a pass at the supplied date.
    ///
    /// The position follows wall time, so replacing a timeline preserves its phase.
    public func phase(at date: Date) -> Int {
        cycleStep(at: date) % stepsPerPass
    }

    /// Builds five minutes of entries and requests a new timeline after four minutes.
    ///
    /// The first entry falls on the two-second boundary at or immediately before
    /// `date`. The final entry falls five minutes after that boundary. Set each
    /// entry's `date` to the date passed to `entry`, and pass that same date to
    /// the marquee view. The overlap lets successive timelines share positions.
    ///
    /// This short cadence is experimental. WidgetKit controls presentation and
    /// reload timing, so entries can remain on screen longer than requested.
    public func timeline<Entry: TimelineEntry>(from date: Date, entry: (Date) -> Entry) -> Timeline<Entry> {
        let start = Date(timeIntervalSinceReferenceDate: absoluteStep(at: date) * secondsPerStep)
        let entries = (0...150).map { index in
            entry(start.addingTimeInterval(Double(index) * secondsPerStep))
        }
        return Timeline(entries: entries, policy: .after(start.addingTimeInterval(240)))
    }

    func lane(at date: Date, copy: Int) -> Int {
        (cycleStep(at: date) + copy * stepsPerPass) % (3 * stepsPerPass)
    }

    func copyCycle(at date: Date, copy: Int) -> Double {
        let step = absoluteStep(at: date) + Double(copy * stepsPerPass)
        return (step / Double(3 * stepsPerPass)).rounded(.down)
    }

    private func cycleStep(at date: Date) -> Int {
        let count = 3 * stepsPerPass
        let remainder = absoluteStep(at: date).truncatingRemainder(dividingBy: Double(count))
        return (Int(remainder) + count) % count
    }

    private func absoluteStep(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate / secondsPerStep).rounded(.down)
    }
}

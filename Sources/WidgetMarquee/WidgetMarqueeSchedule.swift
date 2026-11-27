import Foundation
import WidgetKit

/// Schedules marquee positions on an absolute time grid.
///
/// The default 12-step pass takes 24 seconds when WidgetKit presents each entry.
/// WidgetKit may combine or skip entries and may delay a requested reload.
public struct WidgetMarqueeSchedule: Sendable {
    /// Base interval between scheduled positions in seconds. A pause can add stop and restart entries.
    public let secondsPerStep: TimeInterval

    /// Number of phase indices in one pass through the text.
    public let stepsPerPass: Int

    /// The motion profile used within each full pass.
    public let timing: WidgetMarqueeTiming

    /// Seconds spent at the start of the text after each pass.
    public let pauseBetweenLoops: TimeInterval

    // Legacy linear steps use nil. A zero duration represents stationary text.
    let passDuration: TimeInterval?

    /// Creates a two-second schedule with the specified number of positions per pass.
    ///
    /// More positions reduce the distance between entries for long text. Supported
    /// values are 2 through 3,600 (a scheduled pass of four seconds to two hours).
    public init(stepsPerPass: Int = 12) {
        self.init(stepsPerPass: stepsPerPass, timing: .linear, pauseBetweenLoops: 0)
    }

    /// Creates a two-second schedule with the supplied timing profile.
    public init(stepsPerPass: Int = 12, timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0) {
        precondition((2...3_600).contains(stepsPerPass), "stepsPerPass must be between 2 and 3,600")
        self.stepsPerPass = stepsPerPass
        self.secondsPerStep = 2
        self.timing = timing
        self.pauseBetweenLoops = Self.validPause(pauseBetweenLoops)
        self.passDuration = timing == .linear && self.pauseBetweenLoops == 0 ? nil : Double(stepsPerPass) * 2
    }

    /// Uses a speed in layout points per second, or the default text-dependent duration if omitted.
    /// Speed is the average during travel. The pause is additional time at the start of the text.
    /// Use this schedule with the same text. Nonpositive and nonfinite speeds keep the line stationary.
    public init(
        for text: String, pointsPerSecond: CGFloat? = nil,
        timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0
    ) {
        guard let pointsPerSecond else {
            self = WidgetMarqueeSchedule(
                stepsPerPass: min(3_600, max(12, text.count / 8)), timing: timing, pauseBetweenLoops: pauseBetweenLoops
            )
            return
        }
        self.timing = timing
        self.pauseBetweenLoops = Self.validPause(pauseBetweenLoops)
        let width = WidgetMarqueeMetrics.repeatWidth(for: WidgetMarqueeMetrics.line(from: text))
        let duration = Double(width / pointsPerSecond)
        guard pointsPerSecond.isFinite, pointsPerSecond > 0, duration.isFinite, duration > 0 else {
            self.passDuration = 0
            self.stepsPerPass = 1
            self.secondsPerStep = 2
            return
        }

        self.passDuration = duration
        // WidgetKit samples fast passes more often. Bound the batch size and reload frequency.
        self.secondsPerStep = duration >= 4 ? 2 : (duration >= 2 ? 1 : 0.5)
        self.stepsPerPass = Int(min(3_600, max(2, ceil(duration / secondsPerStep))))
    }

    /// Returns the zero-based position within a pass at the supplied date.
    ///
    /// The position follows wall time, so replacing a timeline preserves its phase.
    public func phase(at date: Date) -> Int {
        if passDuration != nil {
            let fraction = position(at: date, copy: 0).truncatingRemainder(dividingBy: 1)
            return min(stepsPerPass - 1, Int(fraction * Double(stepsPerPass)))
        }
        return cycleStep(at: date) % stepsPerPass
    }

    /// Builds up to 151 entries and requests the next moving batch at its 121st entry.
    ///
    /// The first entry falls on the grid boundary at or immediately before
    /// `date`. A stationary speed produces a single entry. Set each
    /// entry's `date` to the date passed to `entry`, and pass that same date to
    /// the marquee view. The overlap lets successive timelines share positions.
    ///
    /// This short cadence is experimental. WidgetKit controls presentation and
    /// reload timing, so entries can remain on screen longer than requested.
    public func timeline<Entry: TimelineEntry>(from date: Date, entry: (Date) -> Entry) -> Timeline<Entry> {
        timeline(from: date, entryWithNextDate: { date, _ in entry(date) })
    }

    func timeline<Entry: TimelineEntry>(
        from date: Date, entryWithNextDate: (Date, Date?) -> Entry
    ) -> Timeline<Entry> {
        if passDuration == 0 {
            return Timeline(entries: [entryWithNextDate(date, nil)], policy: .never)
        }
        let start = Date(timeIntervalSinceReferenceDate: absoluteStep(at: date) * secondsPerStep)
        var dates = (0...150).map { start.addingTimeInterval(Double($0) * secondsPerStep) }
        // Include the actual stop and restart when a pause falls between grid entries.
        // At sub-sample cycle lengths WidgetKit can only present sampled positions.
        if pauseBetweenLoops > 0, let travel = passDuration, cycleDuration >= secondsPerStep {
            let elapsed = elapsedInCycle(at: start)
            let untilRestart = cycleDuration - elapsed
            let untilStop = elapsed < travel ? travel - elapsed : untilRestart + travel
            let end = dates[150]
            for interval in [untilStop, untilRestart] {
                var boundary = start.addingTimeInterval(interval)
                while boundary < end {
                    dates.append(boundary)
                    let next = boundary.addingTimeInterval(cycleDuration)
                    guard next > boundary else { break }
                    boundary = next
                }
            }
            dates = Array(Set(dates).sorted().prefix(151))
        }
        let entries = dates.indices.map { index in
            let next = passDuration != nil && index + 1 < dates.count ? dates[index + 1] : nil
            return entryWithNextDate(dates[index], next)
        }
        return Timeline(entries: entries, policy: .after(dates[120]))
    }

    // A standalone dated view has no following entry. Use the actual interval
    // since the preceding grid, stop, or restart for its transition to that date.
    func previousSample(before date: Date) -> Date {
        guard pauseBetweenLoops > 0, let pass = passDuration, cycleDuration >= secondsPerStep else {
            return date.addingTimeInterval(-secondsPerStep)
        }
        let time = date.timeIntervalSinceReferenceDate
        let previousGrid = (ceil(time / secondsPerStep) - 1) * secondsPerStep
        let elapsed = elapsedInCycle(at: date)
        let epsilon = max(1e-12, time.ulp * 2)
        let sinceBoundary: TimeInterval
        if elapsed <= epsilon || cycleDuration - elapsed <= epsilon {
            sinceBoundary = pauseBetweenLoops
        } else if elapsed <= pass + epsilon {
            sinceBoundary = elapsed
        } else {
            sinceBoundary = elapsed - pass
        }
        return Date(timeIntervalSinceReferenceDate: max(previousGrid, time - sinceBoundary))
    }

    func lane(at date: Date, copy: Int) -> Int {
        (cycleStep(at: date) + copy * stepsPerPass) % (3 * stepsPerPass)
    }

    // Coordinates in repeats: each copy traverses three lanes before returning offscreen.
    func position(at date: Date, copy: Int) -> Double {
        guard let duration = passDuration else {
            return Double(lane(at: date, copy: copy)) / Double(stepsPerPass)
        }
        guard duration > 0 else { return Double(copy) }
        let coordinate = cycleCoordinate(at: date)
        let lap = floor(coordinate)
        let fraction = min(1, (coordinate - lap) * cycleDuration / duration)
        let lane = (lap + Double(copy) + timing.progress(fraction)).truncatingRemainder(dividingBy: 3)
        return lane < 0 ? lane + 3 : lane
    }

    var cycleDuration: TimeInterval {
        min(.greatestFiniteMagnitude, (passDuration ?? Double(stepsPerPass) * secondsPerStep) + pauseBetweenLoops)
    }

    func elapsedInCycle(at date: Date) -> TimeInterval {
        let coordinate = cycleCoordinate(at: date)
        return (coordinate - floor(coordinate)) * cycleDuration
    }

    private func cycleCoordinate(at date: Date) -> Double {
        let cycle = cycleDuration
        guard cycle > 0 else { return 0 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3 * cycle) / cycle
    }

    func copyCycle(at date: Date, copy: Int) -> Double {
        if let duration = passDuration {
            guard duration > 0 else { return 0 }
            var lap = floor(date.timeIntervalSinceReferenceDate / cycleDuration)
            if pauseBetweenLoops > 0 && elapsedInCycle(at: date) >= duration { lap += 1 }
            return lap.isFinite ? floor((lap + Double(copy)) / 3) : 0
        }
        let step = absoluteStep(at: date) + Double(copy * stepsPerPass)
        return (step / Double(3 * stepsPerPass)).rounded(.down)
    }

    private static func validPause(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite && seconds > 0 ? seconds : 0
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

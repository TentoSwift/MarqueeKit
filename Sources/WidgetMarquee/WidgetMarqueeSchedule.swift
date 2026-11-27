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
    private var groupCycle: (start: Date, duration: TimeInterval)?
    private var groupMotion: WidgetMarqueeGroup.Motion?

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
        let width = WidgetMarqueeMetrics.repeatWidth(for: WidgetMarqueeMetrics.line(from: text))
        let duration = pointsPerSecond.isFinite && pointsPerSecond > 0 ? Double(width / pointsPerSecond) : 0
        self.init(travel: duration, timing: timing, pause: pauseBetweenLoops)
    }

    init(_ row: WidgetMarqueeGroup.Row) {
        self.init(travel: row.widgetTravelDuration, timing: row.timing,
                  pause: row.widgetCycleDuration - row.widgetTravelDuration)
        groupCycle = (row.startedAt, row.widgetCycleDuration)
        groupMotion = row.widgetMotion
    }

    private init(travel duration: TimeInterval, timing: WidgetMarqueeTiming, pause: TimeInterval) {
        self.timing = timing
        self.pauseBetweenLoops = Self.validPause(pause)
        guard duration.isFinite, duration > 0 else {
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
        Self.timeline(for: [self], from: date) { date, next in
            entryWithNextDate(date, passDuration == nil ? nil : next)
        }
    }

    static func timeline<Entry: TimelineEntry>(
        for schedules: [Self], from date: Date, entryWithNextDate: (Date, Date?) -> Entry
    ) -> Timeline<Entry> {
        let moving = schedules.filter { $0.passDuration != 0 }
        guard let step = moving.map(\.secondsPerStep).min() else {
            return Timeline(entries: [entryWithNextDate(date, nil)], policy: .never)
        }
        let start = Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate / step) * step)
        let end = start.addingTimeInterval(150 * step)
        var samples = Set((0...150).map { start.addingTimeInterval(Double($0) * step) })
        for schedule in moving {
            schedule.insertBoundaries(in: start..<end, minimumInterval: step, into: &samples)
        }
        let dates = Array(samples.sorted().prefix(151))
        let entries = dates.indices.map { index in
            let next = index + 1 < dates.count ? dates[index + 1] : nil
            return entryWithNextDate(dates[index], next)
        }
        return Timeline(entries: entries, policy: .after(dates[min(120, dates.count - 1)]))
    }

    private func insertBoundaries(in range: Range<Date>, minimumInterval: TimeInterval,
                                  into dates: inout Set<Date>) {
        guard let travel = passDuration, groupCycle != nil || pauseBetweenLoops > 0 else { return }
        let origin = groupCycle?.start ?? Date(timeIntervalSinceReferenceDate: 0)
        if groupCycle != nil, range.contains(origin) { dates.insert(origin) }
        guard cycleDuration >= minimumInterval else { return }

        // Derive each stop/restart from the epoch so overlapping reloads
        // publish the same dates, even when a pass lasts a fractional second.
        var lap = floor(range.lowerBound.timeIntervalSince(origin) / cycleDuration)
        if groupCycle != nil { lap = max(0, lap) }
        while lap.isFinite {
            let lapStart = origin.addingTimeInterval(lap * cycleDuration)
            guard lapStart < range.upperBound else { break }
            if range.contains(lapStart) { dates.insert(lapStart) }
            if let groupMotion {
                for boundary in [groupMotion.accelerationDuration, groupMotion.decelerationStart] {
                    let change = lapStart.addingTimeInterval(boundary)
                    if range.contains(change) { dates.insert(change) }
                }
            }
            if pauseBetweenLoops > 0 {
                let stop = lapStart.addingTimeInterval(travel)
                if range.contains(stop) { dates.insert(stop) }
            }
            guard lap + 1 > lap else { break }
            lap += 1
        }
    }

    // A standalone dated view has no following entry. Use the actual interval
    // since the preceding grid, stop, or restart for its transition to that date.
    func previousSample(before date: Date) -> Date {
        guard groupCycle != nil || pauseBetweenLoops > 0, let pass = passDuration, cycleDuration >= secondsPerStep else {
            return date.addingTimeInterval(-secondsPerStep)
        }
        let time = date.timeIntervalSinceReferenceDate
        let previousGrid = (ceil(time / secondsPerStep) - 1) * secondsPerStep
        let elapsed = elapsedInCycle(at: date)
        let epsilon = max(1e-12, time.ulp * 2)
        let sinceBoundary: TimeInterval
        if elapsed <= epsilon || cycleDuration - elapsed <= epsilon {
            sinceBoundary = pauseBetweenLoops > 0 ? pauseBetweenLoops : cycleDuration - (groupMotion?.decelerationStart ?? 0)
        } else if elapsed > pass + epsilon {
            sinceBoundary = elapsed - pass
        } else {
            let previousBoundary = groupMotion.flatMap {
                [$0.accelerationDuration, $0.decelerationStart].last { $0 < elapsed - epsilon }
            } ?? 0
            sinceBoundary = elapsed - previousBoundary
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
        let elapsed = (coordinate - lap) * cycleDuration
        let progress = groupMotion?.progress(at: elapsed) ?? timing.progress(min(1, elapsed / duration))
        let lane = (lap + Double(copy) + progress).truncatingRemainder(dividingBy: 3)
        return lane < 0 ? lane + 3 : lane
    }

    var cycleDuration: TimeInterval {
        groupCycle?.duration ?? min(.greatestFiniteMagnitude, (passDuration ?? Double(stepsPerPass) * secondsPerStep) + pauseBetweenLoops)
    }

    func elapsedInCycle(at date: Date) -> TimeInterval {
        let coordinate = cycleCoordinate(at: date)
        return (coordinate - floor(coordinate)) * cycleDuration
    }

    var cruiseFactor: Double? { groupMotion?.cruiseFactor }

    func speedFactor(at date: Date, pass: TimeInterval) -> Double {
        let elapsed = elapsedInCycle(at: date)
        return groupMotion?.speedFactor(at: elapsed) ?? timing.speedFactor(min(1, elapsed / pass))
    }

    private func cycleCoordinate(at date: Date) -> Double {
        let cycle = cycleDuration
        guard cycle > 0 else { return 0 }
        return clockTime(at: date).truncatingRemainder(dividingBy: 3 * cycle) / cycle
    }

    private func clockTime(at date: Date) -> TimeInterval {
        guard let groupCycle else { return date.timeIntervalSinceReferenceDate }
        return max(0, date.timeIntervalSince(groupCycle.start))
    }

    func copyCycle(at date: Date, copy: Int) -> Double {
        if let duration = passDuration {
            guard duration > 0 else { return 0 }
            var lap = floor(clockTime(at: date) / cycleDuration)
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

import UIKit
import WidgetKit

/// Schedules marquee positions on an absolute time grid.
///
/// The default 12-step pass takes 24 seconds when WidgetKit presents each entry.
/// WidgetKit may combine or skip entries and may delay a requested reload.
public struct WidgetMarqueeSchedule: Sendable {
    /// The scrolling direction used to measure the text and draw this schedule.
    public let axis: MarqueeAxis
    /// Custom font for horizontal text. The default is 14-point monospaced.
    public let horizontalFont: UIFont?

    /// Distance in points between consecutive copies. Defaults to 28 points.
    public let repeatSpacing: CGFloat

    /// Base interval between scheduled positions in seconds. A pause can add stop and restart entries.
    public let secondsPerStep: TimeInterval

    /// Number of phase indices in one pass through the text.
    public let stepsPerPass: Int

    /// The motion profile used within each full pass.
    public let timing: WidgetMarqueeTiming

    /// Custom ramps used in place of the preset timing curve.
    public let ramps: MarqueeRamps?

    /// Seconds spent at the start of the text after each pass.
    public let pauseBetweenLoops: TimeInterval

    // Legacy linear steps use nil. A zero duration represents stationary text.
    let passDuration: TimeInterval?
    private var groupCycle: (start: Date, duration: TimeInterval)?
    private var motion: WidgetMarqueeGroup.Motion?

    /// Creates a two-second schedule with the specified number of positions per pass.
    ///
    /// More positions reduce the distance between entries for long text. Supported
    /// values are 2 through 3,600 (a scheduled pass of four seconds to two hours).
    public init(stepsPerPass: Int = 12) {
        self.init(stepsPerPass: stepsPerPass, timing: .linear, pauseBetweenLoops: 0)
    }

    /// Creates a two-second schedule with the supplied timing profile.
    public init(stepsPerPass: Int = 12, timing: WidgetMarqueeTiming = .linear,
                pauseBetweenLoops: TimeInterval = 0, axis: MarqueeAxis = .horizontal, horizontalFont: UIFont? = nil,
                repeatSpacing: CGFloat? = nil, ramps: MarqueeRamps? = nil) {
        precondition((2...3_600).contains(stepsPerPass), "stepsPerPass must be between 2 and 3,600")
        self.axis = axis
        self.horizontalFont = horizontalFont
        self.repeatSpacing = WidgetMarqueeMetrics.normalizedRepeatSpacing(repeatSpacing) ?? WidgetMarqueeMetrics.gap
        self.stepsPerPass = stepsPerPass
        self.secondsPerStep = 2
        self.timing = timing
        self.pauseBetweenLoops = Self.validPause(pauseBetweenLoops)
        self.ramps = ramps
        let travel = Double(stepsPerPass) * 2
        self.motion = ramps.flatMap { WidgetMarqueeGroup.Motion.custom($0, baseTravel: travel, fixedDuration: true) }
        self.passDuration = timing == .linear && self.pauseBetweenLoops == 0 && ramps == nil ? nil : travel
    }

    /// Uses a speed in layout points per second, or the default text-dependent duration if omitted.
    /// Speed is the travel average for preset timing, and the cruise speed with custom ramps.
    /// The pause is additional time at the start of the text.
    /// Use this schedule with the same text. Nonpositive and nonfinite speeds keep the line stationary.
    public init(
        for text: String, pointsPerSecond: CGFloat? = nil,
        timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
        axis: MarqueeAxis = .horizontal, horizontalFont: UIFont? = nil, repeatSpacing: CGFloat? = nil,
        ramps: MarqueeRamps? = nil
    ) {
        guard let pointsPerSecond else {
            self = WidgetMarqueeSchedule(
                stepsPerPass: min(3_600, max(12, text.count / 8)), timing: timing,
                pauseBetweenLoops: pauseBetweenLoops, axis: axis, horizontalFont: horizontalFont, repeatSpacing: repeatSpacing,
                ramps: ramps
            )
            return
        }
        let line = WidgetMarqueeMetrics.line(from: text)
        let spacing = WidgetMarqueeMetrics.normalizedRepeatSpacing(repeatSpacing) ?? WidgetMarqueeMetrics.gap
        let period = WidgetMarqueeMetrics.contentLength(for: line, axis: axis, horizontalFont: horizontalFont) + spacing
        let duration = pointsPerSecond.isFinite && pointsPerSecond > 0 ? Double(period / pointsPerSecond) : 0
        let motion = ramps.flatMap { WidgetMarqueeGroup.Motion.custom($0, baseTravel: duration, fixedDuration: false) }
        self.init(travel: motion?.duration ?? duration, timing: timing, pause: pauseBetweenLoops, axis: axis,
                  horizontalFont: horizontalFont, repeatSpacing: spacing, ramps: ramps, motion: motion)
    }

    init(_ row: WidgetMarqueeGroup.Row) {
        self.init(travel: row.widgetTravelDuration, timing: row.timing,
                  pause: row.widgetCycleDuration - row.widgetTravelDuration, axis: row.axis, horizontalFont: row.horizontalFont,
                  repeatSpacing: row.repeatSpacing ?? WidgetMarqueeMetrics.gap, ramps: row.ramps, motion: row.widgetMotion)
        groupCycle = (row.startedAt, row.widgetCycleDuration)
    }

    private init(travel duration: TimeInterval, timing: WidgetMarqueeTiming, pause: TimeInterval, axis: MarqueeAxis,
                 horizontalFont: UIFont?, repeatSpacing: CGFloat, ramps: MarqueeRamps?, motion: WidgetMarqueeGroup.Motion?) {
        self.ramps = ramps
        self.motion = motion
        self.axis = axis
        self.horizontalFont = horizontalFont
        self.repeatSpacing = repeatSpacing
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
        guard let travel = passDuration, groupCycle != nil || motion != nil || pauseBetweenLoops > 0 else { return }
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
            if let motion {
                for boundary in [motion.accelerationDuration, motion.decelerationStart] {
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
        guard groupCycle != nil || motion != nil || pauseBetweenLoops > 0, let pass = passDuration, cycleDuration >= secondsPerStep else {
            return date.addingTimeInterval(-secondsPerStep)
        }
        let time = date.timeIntervalSinceReferenceDate
        let previousGrid = (ceil(time / secondsPerStep) - 1) * secondsPerStep
        let elapsed = elapsedInCycle(at: date)
        let epsilon = max(1e-12, time.ulp * 2)
        let cycleTime = elapsed <= epsilon || cycleDuration - elapsed <= epsilon ? cycleDuration : elapsed
        let boundaries = [motion?.accelerationDuration, motion?.decelerationStart, pass]
        let previous = boundaries.compactMap { $0 }.last { $0 < cycleTime - epsilon } ?? 0
        return Date(timeIntervalSinceReferenceDate: max(previousGrid, time - (cycleTime - previous)))
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
        let progress = motion?.progress(at: elapsed) ?? timing.progress(min(1, elapsed / duration))
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

    var cruiseFactor: Double? { motion?.cruiseFactor }

    func speedFactor(at date: Date, pass: TimeInterval, arriving: Bool = false) -> Double {
        let elapsed = elapsedInCycle(at: date)
        if arriving, let motion {
            // Use the last ramp's incoming slope, even when the endpoint
            // wraps to zero and the next lap starts at a different speed.
            let tolerance = 2 * date.timeIntervalSinceReferenceDate.ulp
            if abs(elapsed - pass) <= tolerance || (pauseBetweenLoops == 0 && elapsed <= tolerance) {
                return motion.decelerationDuration == 0 ? motion.cruiseFactor : 0
            }
        }
        return motion?.speedFactor(at: elapsed) ?? timing.speedFactor(min(1, elapsed / pass))
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

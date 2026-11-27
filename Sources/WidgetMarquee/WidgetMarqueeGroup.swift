import Foundation

/// Coordinates the start of each pass across two or more marquee rows.
///
/// Each row travels at its own speed, then waits at the head of its text.
/// Eased rows slow together as each one finishes. The remaining eased rows
/// accelerate together through the next part of their pass.
/// The group's pause begins when its last moving row arrives. Keep `startedAt`
/// stable when rebuilding the group or requesting the next widget timeline.
public struct WidgetMarqueeGroup: Sendable {
    /// A message and optional overrides for its row in the group.
    public struct Item: Sendable {
        public let text: String
        public let pointsPerSecond: CGFloat?
        public let timing: WidgetMarqueeTiming?
        public let viewportWidth: CGFloat?

        /// Supply the available text width when rows have different widths or speeds.
        /// A message that fits in this width does not extend the group's cycle.
        public init(_ text: String, pointsPerSecond: CGFloat? = nil, timing: WidgetMarqueeTiming? = nil,
                    viewportWidth: CGFloat? = nil) {
            self.text = text
            self.pointsPerSecond = pointsPerSecond
            self.timing = timing
            self.viewportWidth = viewportWidth
        }
    }

    /// A row with its group's clock. Pass it to `WidgetMarquee` or `LiveActivityMarquee`.
    public struct Row: Identifiable, Sendable {
        /// The index in the supplied array. Duplicate messages remain separate rows.
        public let id: Int
        public let text: String
        public let pointsPerSecond: CGFloat
        public let timing: WidgetMarqueeTiming
        let startedAt: Date
        let widgetTravelDuration: TimeInterval
        let widgetCycleDuration: TimeInterval
        let widgetMotion: Motion?
        let liveTravelDuration: TimeInterval
        let liveCycleDuration: TimeInterval
        let liveMotion: Motion?
    }

    /// Arrival times are also distances expressed in seconds at the specified
    /// average speed. Easing that shared coordinate keeps displacements in
    /// points equal for equally fast rows until the shorter one completes.
    struct Motion: Sendable {
        let groupArrivals: [TimeInterval]
        let arrivals: ArraySlice<TimeInterval>
        let duration: TimeInterval

        static func profiles(for durations: [TimeInterval], timings: [WidgetMarqueeTiming]) -> [TimeInterval: Motion] {
            let arrivals = Set(zip(durations, timings).compactMap { duration, timing in
                duration > 0 && timing == .easeInOut ? duration : nil
            }).sorted()
            guard arrivals.count > 1 else { return [:] }
            // Give even the first row the shared profile so Live Activity rows
            // sample the same phase grid while moving together.
            return Dictionary(uniqueKeysWithValues: arrivals.indices.map { index in
                let duration = arrivals[index]
                return (duration, Motion(groupArrivals: arrivals, arrivals: arrivals[...index], duration: duration))
            })
        }

        func progress(at elapsed: TimeInterval) -> Double {
            guard elapsed > 0 else { return 0 }
            guard elapsed < duration else { return 1 }
            let segment = segment(at: elapsed)
            return (segment.start + segment.length * WidgetMarqueeTiming.easeInOut.progress(segment.fraction)) / duration
        }

        func speedFactor(at elapsed: TimeInterval) -> Double {
            guard elapsed > 0 && elapsed < duration else { return 0 }
            return WidgetMarqueeTiming.easeInOut.speedFactor(segment(at: elapsed).fraction)
        }

        private func segment(at elapsed: TimeInterval) -> (start: TimeInterval, length: TimeInterval, fraction: Double) {
            var lower = arrivals.startIndex
            var upper = arrivals.endIndex - 1
            while lower < upper {
                let mid = lower + (upper - lower) / 2
                if arrivals[mid] < elapsed {
                    lower = mid + 1
                } else {
                    upper = mid
                }
            }
            let start = lower == arrivals.startIndex ? 0 : arrivals[lower - 1]
            let length = arrivals[lower] - start
            return (start, length, (elapsed - start) / length)
        }
    }

    public let rows: [Row]
    public let startedAt: Date

    /// Creates synchronized rows with the same speed and timing.
    public init(_ texts: [String], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
                viewportWidth: CGFloat? = nil) {
        self.init(items: texts.map { Item($0, viewportWidth: viewportWidth) }, startedAt: startedAt,
                  pointsPerSecond: pointsPerSecond, timing: timing, pauseBetweenLoops: pauseBetweenLoops)
    }

    /// Creates synchronized rows with per-item overrides and one pause after the last arrival.
    public init(items: [Item], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0) {
        self.startedAt = startedAt
        let travel = items.map { Self.durations(for: $0, defaultSpeed: pointsPerSecond) }
        let widgetDurations = travel.map(\.widget)
        let liveDurations = travel.map(\.live)
        let timings = items.map { $0.timing ?? timing }
        let widgetMotions = Motion.profiles(for: widgetDurations, timings: timings)
        let liveMotions = Motion.profiles(for: liveDurations, timings: timings)
        let pause = pauseBetweenLoops.isFinite && pauseBetweenLoops > 0 ? pauseBetweenLoops : 0
        let widgetCycle = Self.cycle(longest: widgetDurations.max() ?? 0, pause: pause)
        let liveCycle = Self.cycle(longest: liveDurations.max() ?? 0, pause: pause)
        self.rows = items.indices.map { index in
            let item = items[index]
            return Row(id: index, text: item.text, pointsPerSecond: item.pointsPerSecond ?? pointsPerSecond,
                       timing: timings[index], startedAt: startedAt,
                       widgetTravelDuration: travel[index].widget, widgetCycleDuration: widgetCycle,
                       widgetMotion: timings[index] == .easeInOut ? widgetMotions[travel[index].widget] : nil,
                       liveTravelDuration: travel[index].live, liveCycleDuration: liveCycle,
                       liveMotion: timings[index] == .easeInOut ? liveMotions[travel[index].live] : nil)
        }
    }

    private static func durations(for item: Item, defaultSpeed: CGFloat) -> (widget: TimeInterval, live: TimeInterval) {
        let speed = item.pointsPerSecond ?? defaultSpeed
        guard speed > 0, speed.isFinite else { return (0, 0) }
        let line = WidgetMarqueeMetrics.line(from: item.text)
        guard line.contains(where: { !$0.isWhitespace }) else { return (0, 0) }
        let textWidth = WidgetMarqueeMetrics.textWidth(for: line)
        if let width = item.viewportWidth {
            guard width > 0, textWidth > width else { return (0, 0) }
        }

        let widget = Double((textWidth + WidgetMarqueeMetrics.gap) / speed)
        // The Live Activity renderer uses four measured spaces between copies and
        // shows oversized ActivityKit messages as stationary text.
        let live = item.text.utf8.count <= 4096 ? Double(WidgetMarqueeMetrics.liveRepeatWidth(for: line) / speed) : 0
        return (widget.isFinite ? widget : 0, live.isFinite ? live : 0)
    }

    private static func cycle(longest: TimeInterval, pause: TimeInterval) -> TimeInterval {
        longest > 0 ? min(.greatestFiniteMagnitude, longest + pause) : 0
    }
}

import Foundation

/// Coordinates the start of each pass across two or more marquee rows.
///
/// Each row travels at its own speed, then waits at the head of its text.
/// Eased rows accelerate together, then each slows only for its own finish.
/// The group's pause begins when its last moving row arrives. Keep `startedAt`
/// stable when rebuilding the group or requesting the next widget timeline.
public struct WidgetMarqueeGroup: Sendable {
    /// A message and optional overrides for its row in the group.
    public struct Item: Sendable {
        public let text: String
        public let pointsPerSecond: CGFloat?
        public let timing: WidgetMarqueeTiming?
        /// The available width for horizontal scrolling or height for vertical scrolling.
        public let viewportLength: CGFloat?
        public var viewportWidth: CGFloat? { viewportLength }

        /// Supply the available text width when rows have different widths or speeds.
        /// A message that fits in this width does not extend the group's cycle.
        public init(_ text: String, pointsPerSecond: CGFloat? = nil, timing: WidgetMarqueeTiming? = nil,
                    viewportWidth: CGFloat? = nil) {
            self.init(text, pointsPerSecond: pointsPerSecond, timing: timing, viewportLength: viewportWidth)
        }

        /// Exclude messages that fit along the group's scrolling axis.
        public init(_ text: String, pointsPerSecond: CGFloat? = nil, timing: WidgetMarqueeTiming? = nil,
                    viewportLength: CGFloat?) {
            self.text = text
            self.pointsPerSecond = pointsPerSecond
            self.timing = timing
            self.viewportLength = viewportLength
        }
    }

    /// A row with its group's clock. Pass it to `WidgetMarquee` or `LiveActivityMarquee`.
    public struct Row: Identifiable, Sendable {
        /// The index in the supplied array. Duplicate messages remain separate rows.
        public let id: Int
        public let axis: MarqueeAxis
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

    /// Each row integrates a shared acceleration and cruise speed, followed
    /// by its own deceleration. The area under its speed curve is one pass.
    struct Motion: Sendable {
        let duration: TimeInterval
        let accelerationDuration: TimeInterval
        let decelerationDuration: TimeInterval
        let cruiseFactor: Double

        var decelerationStart: TimeInterval { duration - decelerationDuration }

        static func profiles(for durations: [TimeInterval], timings: [WidgetMarqueeTiming]) -> [TimeInterval: Motion] {
            let moving = Set(zip(durations, timings).compactMap { duration, timing in
                duration > 0 && timing == .easeInOut ? duration : nil
            })
            guard let shortest = moving.min(), let longest = moving.max(), shortest < longest else { return [:] }
            // Each velocity ramp averages half the cruise speed. Reserve at most
            // 1.5 seconds or a third of a pass for both ramps combined.
            let lossFraction = min(1.0 / 6, 0.75 / longest)
            let acceleration = lossFraction * shortest
            let cruiseFactor = 1 / (1 - lossFraction)
            return Dictionary(uniqueKeysWithValues: moving.map { duration in
                let deceleration = (2 * lossFraction) * duration - acceleration
                return (duration, Motion(duration: duration, accelerationDuration: acceleration,
                                         decelerationDuration: deceleration, cruiseFactor: cruiseFactor))
            })
        }

        func progress(at elapsed: TimeInterval) -> Double {
            guard elapsed > 0 else { return 0 }
            guard elapsed < duration else { return 1 }
            if elapsed < accelerationDuration {
                return 0.5 * cruiseFactor * (elapsed / duration) * (elapsed / accelerationDuration)
            }
            if elapsed < decelerationStart {
                return cruiseFactor * ((elapsed - 0.5 * accelerationDuration) / duration)
            }
            let remaining = duration - elapsed
            return 1 - 0.5 * cruiseFactor * (remaining / duration) * (remaining / decelerationDuration)
        }

        func speedFactor(at elapsed: TimeInterval) -> Double {
            guard elapsed > 0 && elapsed < duration else { return 0 }
            if elapsed < accelerationDuration { return cruiseFactor * (elapsed / accelerationDuration) }
            if elapsed < decelerationStart { return cruiseFactor }
            return cruiseFactor * ((duration - elapsed) / decelerationDuration)
        }
    }

    public let rows: [Row]
    public let startedAt: Date

    /// Creates synchronized rows with the same speed and timing.
    public init(_ texts: [String], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
                viewportWidth: CGFloat? = nil) {
        self.init(texts, startedAt: startedAt, pointsPerSecond: pointsPerSecond, timing: timing,
                  pauseBetweenLoops: pauseBetweenLoops, axis: .horizontal, viewportLength: viewportWidth)
    }

    /// Creates synchronized rows or upright columns. Supply their available width or height
    /// so a message that fits does not hold up the other members.
    public init(_ texts: [String], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
                axis: MarqueeAxis, viewportLength: CGFloat? = nil) {
        self.init(items: texts.map { Item($0, viewportLength: viewportLength) }, startedAt: startedAt,
                  pointsPerSecond: pointsPerSecond, timing: timing, pauseBetweenLoops: pauseBetweenLoops, axis: axis)
    }

    /// Creates synchronized rows with per-item overrides and one pause after the last arrival.
    public init(items: [Item], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0, axis: MarqueeAxis = .horizontal) {
        self.startedAt = startedAt
        let travel = items.map { Self.durations(for: $0, defaultSpeed: pointsPerSecond, axis: axis) }
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
            return Row(id: index, axis: axis, text: item.text, pointsPerSecond: item.pointsPerSecond ?? pointsPerSecond,
                       timing: timings[index], startedAt: startedAt,
                       widgetTravelDuration: travel[index].widget, widgetCycleDuration: widgetCycle,
                       widgetMotion: timings[index] == .easeInOut ? widgetMotions[travel[index].widget] : nil,
                       liveTravelDuration: travel[index].live, liveCycleDuration: liveCycle,
                       liveMotion: timings[index] == .easeInOut ? liveMotions[travel[index].live] : nil)
        }
    }

    private static func durations(for item: Item, defaultSpeed: CGFloat, axis: MarqueeAxis) -> (widget: TimeInterval, live: TimeInterval) {
        let speed = item.pointsPerSecond ?? defaultSpeed
        guard speed > 0, speed.isFinite else { return (0, 0) }
        let line = WidgetMarqueeMetrics.line(from: item.text)
        guard line.contains(where: { !$0.isWhitespace }) else { return (0, 0) }
        let textLength = WidgetMarqueeMetrics.contentLength(for: line, axis: axis)
        if let viewport = item.viewportLength {
            guard viewport > 0, textLength > viewport else { return (0, 0) }
        }

        let period = textLength + WidgetMarqueeMetrics.gap
        let widget = Double(period / speed)
        let liveFits = item.text.utf8.count <= 4096 && (axis != .vertical || LiveActivityVerticalStrip.supportsAnimation(line))
        // The horizontal Live Activity strip uses four measured spaces between copies.
        let livePeriod = axis == .vertical ? period : WidgetMarqueeMetrics.liveRepeatWidth(for: line)
        let live = liveFits ? Double(livePeriod / speed) : 0
        return (widget.isFinite ? widget : 0, live.isFinite ? live : 0)
    }

    private static func cycle(longest: TimeInterval, pause: TimeInterval) -> TimeInterval {
        longest > 0 ? min(.greatestFiniteMagnitude, longest + pause) : 0
    }
}

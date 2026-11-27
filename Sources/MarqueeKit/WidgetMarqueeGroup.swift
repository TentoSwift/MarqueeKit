import UIKit

/// Coordinates the start of each pass across two or more marquee rows.
///
/// Each row travels at its own speed, then waits at the head of its text.
/// Eased rows accelerate together, then each slows only for its own finish.
/// The group's pause begins when its last moving row arrives. Keep `startedAt`
/// stable when rebuilding the group or requesting the next widget timeline.
public struct WidgetMarqueeGroup: Sendable {
    /// A message and optional overrides for its row in the group.
    /// An item's ramps or timing take precedence over the group's. When both
    /// are specified on the same item, its ramps control the motion.
    public struct Item: Sendable {
        public let text: String
        public let pointsPerSecond: CGFloat?
        public let timing: WidgetMarqueeTiming?
        /// Font used for both the horizontal line and its travel distance.
        public let horizontalFont: UIFont?
        /// Distance between copies in points. Omit to inherit the group setting.
        public let repeatSpacing: CGFloat?
        public let ramps: MarqueeRamps?
        /// The available width for horizontal scrolling or height for vertical scrolling.
        public let viewportLength: CGFloat?
        public var viewportWidth: CGFloat? { viewportLength }

        /// Supply the available text width when rows have different widths or speeds.
        /// A message that fits in this width does not extend the group's cycle.
        public init(_ text: String, pointsPerSecond: CGFloat? = nil, timing: WidgetMarqueeTiming? = nil,
                    viewportWidth: CGFloat? = nil, horizontalFont: UIFont? = nil, repeatSpacing: CGFloat? = nil,
                    ramps: MarqueeRamps? = nil) {
            self.init(text, pointsPerSecond: pointsPerSecond, timing: timing, viewportLength: viewportWidth,
                      horizontalFont: horizontalFont, repeatSpacing: repeatSpacing, ramps: ramps)
        }

        /// Exclude messages that fit along the group's scrolling axis.
        public init(_ text: String, pointsPerSecond: CGFloat? = nil, timing: WidgetMarqueeTiming? = nil,
                    viewportLength: CGFloat?, horizontalFont: UIFont? = nil, repeatSpacing: CGFloat? = nil,
                    ramps: MarqueeRamps? = nil) {
            self.text = text
            self.pointsPerSecond = pointsPerSecond
            self.timing = timing
            self.viewportLength = viewportLength
            self.horizontalFont = horizontalFont
            self.repeatSpacing = repeatSpacing
            self.ramps = ramps
        }
    }

    /// A row with its group's clock. Pass it to `WidgetMarquee` or `LiveActivityMarquee`.
    public struct Row: Identifiable, Sendable {
        /// The index in the supplied array. Duplicate messages remain separate rows.
        public let id: Int
        public let axis: MarqueeAxis
        /// The effective point spacing, or nil for the surface's default.
        public let repeatSpacing: CGFloat?
        public let ramps: MarqueeRamps?
        public let horizontalFont: UIFont?
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
        var accelerationCurve: MarqueeRamps.Curve = .linear
        var decelerationCurve: MarqueeRamps.Curve = .linear

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

        /// baseTravel is either the time to travel the distance at cruise speed,
        /// or the prescribed total time when no explicit speed was provided.
        static func custom(_ ramps: MarqueeRamps, baseTravel: TimeInterval, fixedDuration: Bool) -> Motion? {
            guard baseTravel.isFinite, baseTravel > 0 else { return nil }
            var up = ramps.acceleration.duration
            var down = ramps.deceleration.duration
            let upArea = ramps.acceleration.curve.averageSpeed(through: 1)
            let downArea = ramps.deceleration.curve.averageSpeed(through: 1)
            let largest = max(up, down)
            if largest > 0 {
                // Work in units of the longest ramp so even two maximum finite
                // requested durations retain their ratio when fitted to a short pass.
                let upRatio = up / largest
                let downRatio = down / largest
                let required = fixedDuration ? upRatio + downRatio : upRatio * upArea + downRatio * downArea
                let limit = baseTravel / required
                if largest > limit {
                    up = limit * upRatio
                    down = limit * downRatio
                }
            }
            let duration = fixedDuration ? baseTravel : baseTravel + up * (1 - upArea) + down * (1 - downArea)
            guard duration.isFinite else {
                return custom(ramps, baseTravel: .greatestFiniteMagnitude, fixedDuration: true)
            }
            let cruise = fixedDuration
                ? 1 / (1 - (up / duration) * (1 - upArea) - (down / duration) * (1 - downArea))
                : duration / baseTravel
            return Motion(duration: duration, accelerationDuration: up, decelerationDuration: down, cruiseFactor: cruise,
                          accelerationCurve: ramps.acceleration.curve, decelerationCurve: ramps.deceleration.curve)
        }

        func progress(at elapsed: TimeInterval) -> Double {
            guard elapsed > 0 else { return 0 }
            guard elapsed < duration else { return 1 }
            if elapsed < accelerationDuration {
                return cruiseFactor * (elapsed / duration) * accelerationCurve.averageSpeed(through: elapsed / accelerationDuration)
            }
            if elapsed < decelerationStart {
                let launchLoss = accelerationDuration * (1 - accelerationCurve.averageSpeed(through: 1))
                return cruiseFactor * ((elapsed - launchLoss) / duration)
            }
            let remaining = duration - elapsed
            return 1 - cruiseFactor * (remaining / duration) * decelerationCurve.averageSpeed(through: remaining / decelerationDuration)
        }

        func speedFactor(at elapsed: TimeInterval) -> Double {
            guard elapsed >= 0 && elapsed < duration else { return 0 }
            if elapsed < accelerationDuration { return cruiseFactor * accelerationCurve.speed(at: elapsed / accelerationDuration) }
            if elapsed < decelerationStart { return cruiseFactor }
            return cruiseFactor * decelerationCurve.speed(at: (duration - elapsed) / decelerationDuration)
        }
    }

    public let rows: [Row]
    public let startedAt: Date

    /// Creates synchronized rows with the same speed and timing.
    public init(_ texts: [String], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
                viewportWidth: CGFloat? = nil, horizontalFont: UIFont? = nil, repeatSpacing: CGFloat? = nil,
                ramps: MarqueeRamps? = nil) {
        self.init(texts, startedAt: startedAt, pointsPerSecond: pointsPerSecond, timing: timing,
                  pauseBetweenLoops: pauseBetweenLoops, axis: .horizontal, viewportLength: viewportWidth,
                  horizontalFont: horizontalFont, repeatSpacing: repeatSpacing, ramps: ramps)
    }

    /// Creates synchronized rows or upright columns. Supply their available width or height
    /// so a message that fits does not hold up the other members.
    public init(_ texts: [String], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
                axis: MarqueeAxis, viewportLength: CGFloat? = nil, horizontalFont: UIFont? = nil, repeatSpacing: CGFloat? = nil,
                ramps: MarqueeRamps? = nil) {
        self.init(items: texts.map { Item($0, viewportLength: viewportLength, horizontalFont: horizontalFont) },
                  startedAt: startedAt,
                  pointsPerSecond: pointsPerSecond, timing: timing, pauseBetweenLoops: pauseBetweenLoops, axis: axis,
                  repeatSpacing: repeatSpacing, ramps: ramps)
    }

    /// Creates synchronized rows with per-item overrides and one pause after the last arrival.
    public init(items: [Item], startedAt: Date, pointsPerSecond: CGFloat,
                timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0, axis: MarqueeAxis = .horizontal,
                repeatSpacing: CGFloat? = nil,
                ramps: MarqueeRamps? = nil) {
        self.startedAt = startedAt
        let spacings = items.map { WidgetMarqueeMetrics.normalizedRepeatSpacing($0.repeatSpacing ?? repeatSpacing) }
        let travel = zip(items, spacings).map { item, spacing in
            Self.durations(for: item, defaultSpeed: pointsPerSecond, axis: axis, repeatSpacing: spacing)
        }
        let timings = items.map { $0.timing ?? timing }
        let rowRamps = items.map { $0.ramps ?? ($0.timing == nil ? ramps : nil) }
        func playback(_ base: [TimeInterval]) -> [(duration: TimeInterval, motion: Motion?)] {
            let legacyTiming = items.indices.map { rowRamps[$0] == nil ? timings[$0] : .linear }
            let legacy = Motion.profiles(for: base, timings: legacyTiming)
            return items.indices.map { index in
                let motion: Motion?
                if let ramps = rowRamps[index] {
                    motion = Motion.custom(ramps, baseTravel: base[index], fixedDuration: false)
                } else {
                    motion = timings[index] == .easeInOut ? legacy[base[index]] : nil
                }
                return (motion?.duration ?? base[index], motion)
            }
        }
        let widget = playback(travel.map(\.widget))
        let live = playback(travel.map(\.live))
        let pause = pauseBetweenLoops.isFinite && pauseBetweenLoops > 0 ? pauseBetweenLoops : 0
        let widgetCycle = Self.cycle(longest: widget.map(\.duration).max() ?? 0, pause: pause)
        let liveCycle = Self.cycle(longest: live.map(\.duration).max() ?? 0, pause: pause)
        self.rows = items.indices.map { index in
            let item = items[index]
            return Row(id: index, axis: axis, repeatSpacing: spacings[index], ramps: rowRamps[index], horizontalFont: item.horizontalFont,
                       text: item.text, pointsPerSecond: item.pointsPerSecond ?? pointsPerSecond,
                       timing: timings[index], startedAt: startedAt,
                       widgetTravelDuration: widget[index].duration, widgetCycleDuration: widgetCycle,
                       widgetMotion: widget[index].motion,
                       liveTravelDuration: live[index].duration, liveCycleDuration: liveCycle,
                       liveMotion: live[index].motion)
        }
    }

    private static func durations(for item: Item, defaultSpeed: CGFloat, axis: MarqueeAxis,
                                  repeatSpacing: CGFloat?) -> (widget: TimeInterval, live: TimeInterval) {
        let speed = item.pointsPerSecond ?? defaultSpeed
        guard speed > 0, speed.isFinite else { return (0, 0) }
        let line = WidgetMarqueeMetrics.line(from: item.text)
        guard line.contains(where: { !$0.isWhitespace }) else { return (0, 0) }
        let textLength = WidgetMarqueeMetrics.contentLength(for: line, axis: axis, horizontalFont: item.horizontalFont)
        if let viewport = item.viewportLength {
            guard viewport > 0, textLength > viewport else { return (0, 0) }
        }

        let period = textLength + (repeatSpacing ?? WidgetMarqueeMetrics.gap)
        let widget = Double(period / speed)
        let liveFits = item.text.utf8.count <= 4096 && (axis != .vertical || LiveActivityVerticalStrip.supportsAnimation(line))
        let livePeriod = axis == .vertical ? period : WidgetMarqueeMetrics.liveRepeatWidth(
            for: line, font: item.horizontalFont, repeatSpacing: repeatSpacing
        )
        let live = liveFits ? Double(livePeriod / speed) : 0
        return (widget.isFinite ? widget : 0, live.isFinite ? live : 0)
    }

    private static func cycle(longest: TimeInterval, pause: TimeInterval) -> TimeInterval {
        longest > 0 ? min(.greatestFiniteMagnitude, longest + pause) : 0
    }
}

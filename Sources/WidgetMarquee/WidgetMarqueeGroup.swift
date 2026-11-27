import Foundation

/// Coordinates the start of each pass across two or more marquee rows.
///
/// Each row travels at its own speed, then waits at the head of its text.
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
        let liveTravelDuration: TimeInterval
        let liveCycleDuration: TimeInterval
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
        let pause = pauseBetweenLoops.isFinite && pauseBetweenLoops > 0 ? pauseBetweenLoops : 0
        let widgetCycle = Self.cycle(longest: travel.map(\.widget).max() ?? 0, pause: pause)
        let liveCycle = Self.cycle(longest: travel.map(\.live).max() ?? 0, pause: pause)
        self.rows = items.indices.map { index in
            let item = items[index]
            return Row(id: index, text: item.text, pointsPerSecond: item.pointsPerSecond ?? pointsPerSecond,
                       timing: item.timing ?? timing, startedAt: startedAt,
                       widgetTravelDuration: travel[index].widget, widgetCycleDuration: widgetCycle,
                       liveTravelDuration: travel[index].live, liveCycleDuration: liveCycle)
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

import ActivityKit
import SwiftUI
import WidgetKit
import WidgetMarquee

// Add this widget to the extension's existing @main WidgetBundle.
struct MarqueeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MarqueeActivityAttributes.self) { context in
            marquee(context).padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    marquee(context)
                }
            } compactLeading: {
                Image(systemName: "text.alignleft").accessibilityLabel("メッセージ")
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer)
                    .monospacedDigit().frame(width: 44)
                    .accessibilityLabel("開始からの経過時間")
            } minimal: {
                Image(systemName: "text.alignleft").accessibilityLabel("メッセージ")
            }
        }
    }

    @ViewBuilder
    private func marquee(_ context: ActivityViewContext<MarqueeActivityAttributes>) -> some View {
        let speed = context.state.pointsPerSecond.map { CGFloat($0) }
        if let second = context.state.secondText, !second.isEmpty {
            GeometryReader { viewport in
                let group = WidgetMarqueeGroup([context.state.text, second], startedAt: context.attributes.startedAt,
                                               pointsPerSecond: speed ?? 40, timing: .easeInOut, pauseBetweenLoops: 2,
                                               viewportWidth: viewport.size.width)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.rows) { row in LiveActivityMarquee(row) }
                }
            }
            .frame(height: 2 * 23 + 4)
        } else {
            LiveActivityMarquee(context.state.text, startedAt: context.attributes.startedAt,
                               pointsPerSecond: speed, timing: .easeInOut, pauseBetweenLoops: 2)
        }
    }
}

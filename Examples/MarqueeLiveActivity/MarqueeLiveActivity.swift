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

    private func marquee(_ context: ActivityViewContext<MarqueeActivityAttributes>) -> some View {
        LiveActivityMarquee(
            context.state.text, startedAt: context.attributes.startedAt,
            pointsPerSecond: context.state.pointsPerSecond.map { CGFloat($0) },
            timing: .easeInOut, pauseBetweenLoops: 2
        )
    }
}

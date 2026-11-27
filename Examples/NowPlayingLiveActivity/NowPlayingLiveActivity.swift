import ActivityKit
import AppIntents
import MarqueeKit
import SwiftUI
import WidgetKit

// Add this file to the widget extension and register NowPlayingLiveActivity() in its WidgetBundle.
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            NowPlayingCard(state: context.state, activityID: context.activityID)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    NowPlayingCard(state: context.state, activityID: context.activityID, isExpanded: true)
                }
            } compactLeading: {
                RecordCover().frame(width: 21, height: 21)
            } compactTrailing: {
                Image(systemName: context.state.playingFrom == nil ? "pause.fill" : "waveform")
                    .accessibilityLabel(context.state.playingFrom == nil ? "一時停止中" : "再生中")
            } minimal: {
                Image(systemName: "music.note")
            }
            // The shared card already supplies the content margins.
            .contentMargins(.all, 0, for: .expanded)
        }
    }
}

private struct NowPlayingCard: View {
    let state: NowPlayingAttributes.ContentState
    let activityID: String
    var isExpanded = false

    private var coverSize: CGFloat { isExpanded ? 44 : 48 }
    private var controlHeight: CGFloat { isExpanded ? 32 : 44 }

    var body: some View {
        VStack(spacing: isExpanded ? 2 : 5) {
            HStack(spacing: 10) {
                RecordCover().frame(width: coverSize, height: coverSize)
                GeometryReader { area in
                    let group = WidgetMarqueeGroup(
                        [state.track.title, state.track.artist], startedAt: state.titleStartedAt,
                        pointsPerSecond: 32, timing: .easeInOut, pauseBetweenLoops: 2,
                        viewportWidth: area.size.width
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.rows) { row in
                            LiveActivityMarquee(row)
                                .foregroundStyle(row.id == 0 ? Color.white : Color.white.opacity(0.68))
                        }
                    }
                    .marqueeEdgeFade(length: 8, clearance: 4)
                }
                .frame(height: 46)
                Group {
                    if state.playingFrom == nil {
                        Image(systemName: "pause.fill").font(.caption)
                    } else {
                        Image(systemName: "waveform")
                            .foregroundStyle(LinearGradient(colors: [.orange, .pink, .yellow],
                                                            startPoint: .leading, endPoint: .trailing))
                    }
                }
                .frame(width: 20, alignment: .trailing)
                .accessibilityHidden(true)
            }
            progress
            HStack(spacing: 0) {
                control(.favorite, state.favorites.contains(state.trackIndex) ? "star.fill" : "star",
                        "お気に入りを切り替える", size: 17, alignment: isExpanded ? .center : .leading)
                Spacer(minLength: 0)
                control(.previous, "backward.fill", "前の曲")
                Spacer(minLength: 0)
                control(.playPause, state.playingFrom == nil ? "play.fill" : "pause.fill",
                        state.playingFrom == nil ? "再生" : "一時停止", size: 26)
                Spacer(minLength: 0)
                control(.next, "forward.fill", "次の曲")
                Spacer(minLength: 0)
                Image(systemName: "airpodspro")
                    .font(.body).foregroundStyle(.white.opacity(0.65))
                    .frame(width: 44, height: controlHeight, alignment: isExpanded ? .center : .trailing)
                    .accessibilityLabel("デモの出力先：イヤフォン")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
    }

    private var progress: some View {
        HStack(spacing: 7) {
            if let start = state.playingFrom {
                let interval = start...start.addingTimeInterval(state.track.duration)
                Text(timerInterval: interval, countsDown: false).frame(width: 42, alignment: .leading)
                ProgressView(timerInterval: interval, countsDown: false).labelsHidden()
                HStack(spacing: 0) {
                    Text("−")
                    Text(timerInterval: interval, countsDown: true)
                }
                .frame(width: 42, alignment: .trailing)
            } else {
                Text(clock(state.pausedAt)).frame(width: 42, alignment: .leading)
                ProgressView(value: state.pausedAt, total: state.track.duration)
                Text("−" + clock(state.track.duration - state.pausedAt))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.72))
        .progressViewStyle(.linear)
        .tint(.white.opacity(0.85))
    }

    private func clock(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func control(_ action: PlayerAction, _ symbol: String, _ label: String,
                         size: CGFloat = 20, alignment: Alignment = .center) -> some View {
        Button(intent: NowPlayingControl(action, activityID: activityID)) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: controlHeight, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

private struct RecordCover: View {
    var body: some View {
        GeometryReader { view in
            let side = min(view.size.width, view.size.height)
            ZStack {
                LinearGradient(colors: [Color(red: 0.25, green: 0.19, blue: 0.48),
                                        Color(red: 0.94, green: 0.52, blue: 0.45),
                                        Color(red: 0.99, green: 0.83, blue: 0.57)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 1, green: 0.90, blue: 0.70))
                    .frame(width: side * 0.30).offset(x: side * 0.13, y: -side * 0.16)
                Ellipse().fill(Color(red: 0.41, green: 0.34, blue: 0.55))
                    .frame(width: side * 1.7, height: side * 0.68)
                    .rotationEffect(.degrees(-16)).offset(y: side * 0.40)
                Ellipse().fill(Color(red: 0.19, green: 0.18, blue: 0.32))
                    .frame(width: side * 1.6, height: side * 0.52)
                    .rotationEffect(.degrees(14)).offset(y: side * 0.53)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.12))
        }
        .accessibilityHidden(true)
    }
}

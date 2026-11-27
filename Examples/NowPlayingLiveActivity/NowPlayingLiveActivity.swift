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

    private var coverSize: CGFloat { isExpanded ? 48 : 57 }
    private var controlHeight: CGFloat { isExpanded ? 34 : 44 }
    private var secondaryColor: Color { .white.opacity(0.55) }

    var body: some View {
        VStack(spacing: isExpanded ? 1 : 7) {
            HStack(spacing: 4) {
                RecordCover().frame(width: coverSize, height: coverSize)
                GeometryReader { area in
                    let group = WidgetMarqueeGroup(items: [
                        .init(state.track.title, viewportWidth: area.size.width,
                              horizontalFont: .systemFont(ofSize: 18, weight: .semibold)),
                        .init(state.track.artist, viewportWidth: area.size.width,
                              horizontalFont: .systemFont(ofSize: 18))
                    ], startedAt: state.titleStartedAt, pointsPerSecond: 28,
                       timing: .easeInOut, pauseBetweenLoops: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.rows) { row in
                            LiveActivityMarquee(row)
                                .foregroundStyle(row.id == 0 ? .white : secondaryColor)
                        }
                    }
                    .marqueeEdgeFade(length: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: coverSize)
                playbackIndicator
                    .frame(width: 30)
                    .offset(y: isExpanded ? 0 : -10)
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
            }
            progress
            controls
                .offset(y: isExpanded ? -5 : 0)
        }
        .padding(.horizontal, 14)
        // The expanded bottom region begins below the system camera area.
        .padding(.top, isExpanded ? 1 : 14)
        .padding(.bottom, isExpanded ? 11 : 14)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var playbackIndicator: some View {
        if isExpanded && state.playingFrom != nil {
            let heights: [CGFloat] = [21, 14, 19, 21, 22, 17]
            LinearGradient(colors: [Color(red: 0.69, green: 0.46, blue: 0.46),
                                    Color(red: 0.72, green: 0.70, blue: 0.63)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 22, height: 22)
                .mask {
                    HStack(spacing: 1.5) {
                        ForEach(heights.indices, id: \.self) { index in
                            Capsule().frame(width: 2.4, height: heights[index])
                        }
                    }
                }
        } else {
            HStack(spacing: 1.8) {
                ForEach(0..<6) { _ in Circle().frame(width: 1.8, height: 1.8) }
            }
            .foregroundStyle(.white.opacity(0.32))
        }
    }

    private var progress: some View {
        let interval = state.playingFrom.map { $0...$0.addingTimeInterval(state.track.duration) }
        return HStack(spacing: 8) {
            timeLabel(interval: interval, remaining: false)
            Group {
                if let interval {
                    ProgressView(timerInterval: interval, countsDown: false)
                } else {
                    ProgressView(value: state.pausedAt, total: state.track.duration)
                }
            }
            .labelsHidden()
            .progressViewStyle(.linear)
            .tint(.white.opacity(0.55))
            // Slice the middle of the system timer bar for a flat moving edge.
            // The outer capsule rounds only the ends of the entire track.
            .frame(height: 6)
            .scaleEffect(x: 1, y: 8)
            .frame(height: isExpanded ? 5 : 7)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            timeLabel(interval: interval, remaining: true)
        }
        .font(.system(size: isExpanded ? 15 : 20, weight: .medium).monospacedDigit())
        .foregroundStyle(secondaryColor)
        .padding(.horizontal, 6)
    }

    private func timeLabel(interval: ClosedRange<Date>?, remaining: Bool) -> some View {
        let pausedTime = remaining ? state.track.duration - state.pausedAt : state.pausedAt
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if remaining { Text(verbatim: "−") }
            // Reserve the width of m:ss in the actual font, independent of the timer's ideal width.
            Text(verbatim: clock(state.track.duration))
                .hidden()
                .overlay(alignment: .trailing) {
                    if let interval {
                        Text(timerInterval: interval, countsDown: remaining, showsHours: false)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.9)
                    } else {
                        Text(verbatim: clock(pausedTime))
                    }
                }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        let favorite = state.favorites.contains(state.trackIndex)
        return HStack(spacing: 0) {
            control(.favorite, favorite ? "star.fill" : "star",
                    "お気に入りを切り替える", size: isExpanded ? 20 : 23, weight: .regular)
                .foregroundStyle(favorite ? .white : secondaryColor)
            Spacer(minLength: 0)
            control(.previous, "backward.fill", "前の曲", size: isExpanded ? 22 : 25)
            Spacer(minLength: 0)
            control(.playPause, state.playingFrom == nil ? "play.fill" : "pause.fill",
                    state.playingFrom == nil ? "再生" : "一時停止", size: isExpanded ? 32 : 39)
            Spacer(minLength: 0)
            control(.next, "forward.fill", "次の曲", size: isExpanded ? 22 : 25)
            Spacer(minLength: 0)
            Image(systemName: "airpodspro")
                .font(.system(size: isExpanded ? 18 : 25, weight: .regular))
                .foregroundStyle(secondaryColor)
                .frame(width: 44, height: controlHeight)
                .accessibilityLabel("デモの出力先：イヤフォン")
        }
    }

    private func clock(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func control(_ action: PlayerAction, _ symbol: String, _ label: String,
                         size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        Button(intent: NowPlayingControl(action, activityID: activityID)) {
            Image(systemName: symbol).font(.system(size: size, weight: weight))
                .frame(width: 44, height: controlHeight)
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

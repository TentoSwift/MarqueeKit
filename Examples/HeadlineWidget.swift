import AppIntents
import SwiftUI
import WidgetKit
import WidgetMarquee

private let sampleHeadline = "START  ·  東京  →  名古屋  →  京都  →  大阪  →  広島  →  博多  ·  END"

private func schedule(for headline: String) -> WidgetMarqueeSchedule {
    WidgetMarqueeSchedule(stepsPerPass: min(3_600, max(12, headline.count / 8)))
}

struct HeadlineConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "見出しの設定" }

    @Parameter(title: "テキスト")
    var text: String?

    var headline: String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sampleHeadline
        }
        return text
    }
}

private struct HeadlineEntry: TimelineEntry {
    let date: Date
    let headline: String
}

private struct HeadlineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HeadlineEntry {
        HeadlineEntry(date: .now, headline: sampleHeadline)
    }

    func snapshot(for configuration: HeadlineConfiguration, in context: Context) async -> HeadlineEntry {
        HeadlineEntry(date: .now, headline: configuration.headline)
    }

    func timeline(for configuration: HeadlineConfiguration, in context: Context) async -> Timeline<HeadlineEntry> {
        let headline = configuration.headline
        return schedule(for: headline).timeline(from: .now) { date in
            HeadlineEntry(date: date, headline: headline)
        }
    }
}

@main
struct HeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HeadlineWidget", intent: HeadlineConfiguration.self, provider: HeadlineProvider()) { entry in
            WidgetMarquee(entry.headline, date: entry.date, schedule: schedule(for: entry.headline))
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Headline")
        .description("設定した文章が1行に収まらないとき、自動で繰り返し表示します。")
        .supportedFamilies([.systemMedium])
    }
}

import SwiftUI
import WidgetKit
import WidgetMarquee

private let schedule = WidgetMarqueeSchedule()

private struct HeadlineEntry: TimelineEntry {
    let date: Date
    let headline: String
}

private struct HeadlineProvider: TimelineProvider {
    private let headline = "START  ·  東京  →  名古屋  →  京都  →  大阪  →  広島  →  博多  ·  END"

    func placeholder(in context: Context) -> HeadlineEntry {
        HeadlineEntry(date: .now, headline: headline)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadlineEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadlineEntry>) -> Void) {
        completion(schedule.timeline(from: .now) { date in
            HeadlineEntry(date: date, headline: headline)
        })
    }
}

@main
struct HeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeadlineWidget", provider: HeadlineProvider()) { entry in
            WidgetMarquee(entry.headline, date: entry.date, schedule: schedule)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Headline")
        .description("行に収まらない見出しを繰り返し表示します。")
        .supportedFamilies([.systemMedium])
    }
}

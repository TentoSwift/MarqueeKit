import AppIntents
import SwiftUI
import WidgetKit
import MarqueeKit

private let sampleHeadline = "START  ·  東京  →  名古屋  →  京都  →  大阪  →  広島  →  博多  ·  END"

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

private struct HeadlineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetMarqueeEntry {
        WidgetMarqueeEntry(sampleHeadline)
    }

    func snapshot(for configuration: HeadlineConfiguration, in context: Context) async -> WidgetMarqueeEntry {
        WidgetMarqueeEntry(configuration.headline)
    }

    func timeline(for configuration: HeadlineConfiguration, in context: Context) async -> Timeline<WidgetMarqueeEntry> {
        WidgetMarquee.timeline(for: configuration.headline)
    }
}

@main
struct HeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HeadlineWidget", intent: HeadlineConfiguration.self, provider: HeadlineProvider()) { entry in
            WidgetMarquee(entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Headline")
        .description("設定した文章が1行に収まらないとき、自動で繰り返し表示します。")
        .supportedFamilies([.systemMedium])
    }
}

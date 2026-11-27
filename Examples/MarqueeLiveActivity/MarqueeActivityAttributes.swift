import ActivityKit
import Foundation

// Include this file in both the containing app and its widget extension.
struct MarqueeActivityAttributes: ActivityAttributes {
    /// Preserve this date across content updates so the timers share the same clock.
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        let text: String
    }

    enum ContentError: LocalizedError {
        case tooLarge

        var errorDescription: String? {
            "ライブアクティビティに送る文章を短くしてください。"
        }
    }

    func content(for text: String) throws -> ActivityContent<ContentState> {
        let state = ContentState(text: text)
        let encoder = JSONEncoder()
        let attributeBytes = try encoder.encode(self).count
        let stateBytes = try encoder.encode(state).count
        guard attributeBytes + stateBytes <= 4_096 else { throw ContentError.tooLarge }
        return ActivityContent(state: state, staleDate: nil)
    }
}

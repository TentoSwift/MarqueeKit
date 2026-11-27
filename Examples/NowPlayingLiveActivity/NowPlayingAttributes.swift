import ActivityKit
import AppIntents
import Foundation

// Add this file to both the app and the widget extension.
struct NowPlayingAttributes: ActivityAttributes {
    struct Track {
        let title: String
        let artist: String
        let duration: TimeInterval
    }

    static let playlist = [
        Track(title: "夜明けのホームで — Platform Sessions, Vol. 1", artist: "灯台カルテット feat. 海辺の弦楽団", duration: 251),
        Track(title: "小雨の窓辺", artist: "灯台カルテット", duration: 204),
        Track(title: "星を待つあいだ — Observatory Mix", artist: "青のアンサンブル", duration: 227)
    ]

    struct ContentState: Codable, Hashable {
        var trackIndex = 0
        var favorites: Set<Int> = []
        var titleStartedAt: Date
        // While playing, this is the instant at which playback was at zero.
        var playingFrom: Date?
        var pausedAt: TimeInterval = 0

        var track: Track { playlist[trackIndex] }

        mutating func apply(_ action: PlayerAction, at now: Date) {
            switch action {
            case .favorite:
                if !favorites.insert(trackIndex).inserted { favorites.remove(trackIndex) }
            case .playPause:
                if let playingFrom {
                    pausedAt = min(track.duration, max(0, now.timeIntervalSince(playingFrom)))
                    self.playingFrom = nil
                } else {
                    playingFrom = now.addingTimeInterval(-(pausedAt < track.duration ? pausedAt : 0))
                }
            case .previous, .next:
                let step = action == .next ? 1 : -1
                trackIndex = (trackIndex + playlist.count + step) % playlist.count
                titleStartedAt = now
                if playingFrom != nil { playingFrom = now }
                pausedAt = 0
            }
        }
    }

    /// Call from a foreground app. The demo updates the card without playing audio.
    @discardableResult
    static func start() throws -> Activity<Self> {
        let now = Date.now
        let state = ContentState(titleStartedAt: now, playingFrom: now)
        return try Activity.request(attributes: Self(), content: .init(state: state, staleDate: nil),
                                    pushType: nil)
    }
}

enum PlayerAction: String, AppEnum {
    case favorite, previous, playPause, next

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "再生操作"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .favorite: "お気に入りを切り替える", .previous: "前の曲",
        .playPause: "再生と一時停止を切り替える", .next: "次の曲"
    ]
}

struct NowPlayingControl: LiveActivityIntent {
    static var title: LocalizedStringResource = "再生カードを操作"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Live Activity") var activityID: String
    @Parameter(title: "操作") var action: PlayerAction

    init() {}
    init(_ action: PlayerAction, activityID: String) {
        self.action = action
        self.activityID = activityID
    }

    func perform() async throws -> some IntentResult {
        if let activity = Activity<NowPlayingAttributes>.activities.first(where: { $0.id == activityID }) {
            var state = activity.content.state
            state.apply(action, at: .now)
            await activity.update(.init(state: state, staleDate: nil))
        }
        return .result()
    }
}

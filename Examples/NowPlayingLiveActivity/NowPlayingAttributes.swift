import ActivityKit
import AppIntents
import Foundation
import UIKit

// Include this file in the app and the widget extension.
enum PlayerCurve: String, Codable, CaseIterable {
    case linear, easeIn, easeOut

}

struct PlayerMotion: Codable, Hashable {
    enum Style: String, Codable, CaseIterable {
        case linear, easeInOut, custom

        var label: String {
            switch self {
            case .linear: return "等速"
            case .easeInOut: return "自動で加減速"
            case .custom: return "加減速を指定"
            }
        }
    }

    var style: Style = .easeInOut
    var acceleration: Double = 0.5
    var accelerationCurve: PlayerCurve = .easeIn
    var deceleration: Double = 1.5
    var decelerationCurve: PlayerCurve = .easeOut

    func validate() throws {
        try PlayerSettings.check(acceleration, name: "加速時間")
        try PlayerSettings.check(deceleration, name: "減速時間")
    }
}

struct PlayerRow: Codable, Hashable {
    enum Weight: String, Codable, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

        var value: UIFont.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }
    }
    var speed: Double?
    var spacing: Double?
    var motion: PlayerMotion?
    var fontSize: Double = 18
    var weight: Weight = .regular
    var fontName: String = ""

    var font: UIFont {
        if !fontName.isEmpty, let face = UIFont(name: fontName, size: fontSize) { return face }
        return UIFont.systemFont(ofSize: fontSize, weight: weight.value)
    }

    func validate() throws {
        try PlayerSettings.check(speed, name: "行の速度")
        try PlayerSettings.check(spacing, name: "行の周回の余白")
        try motion?.validate()
        try PlayerSettings.check(fontSize, name: "文字サイズ", positive: true)
        if !fontName.isEmpty, UIFont(name: fontName, size: fontSize) == nil {
            throw PlayerSettings.InputError("フォント「\(fontName)」が見つかりません。PostScript名を確認してください。")
        }
    }
}

struct PlayerSettings: Codable, Hashable {
    enum Direction: String, Codable, CaseIterable { case horizontal, vertical }
    struct Labels: Codable, Hashable {
        var title: String?
        var artist: String?
    }

    var labels: [Int: Labels] = [:]
    var speed: Double? = 28
    var motion = PlayerMotion()
    var pause: Double = 2
    var spacing: Double?
    var fade: Double = 6
    var clearance: Double = 0
    var direction = Direction.horizontal
    var synchronized = true
    var titleRow = PlayerRow(weight: .semibold)
    var artistRow = PlayerRow()

    func track(_ index: Int) -> NowPlayingAttributes.Track {
        let base = NowPlayingAttributes.playlist[index]
        return .init(title: labels[index]?.title ?? base.title,
                     artist: labels[index]?.artist ?? base.artist, duration: base.duration)
    }

    mutating func setText(_ text: String, for index: Int, title: Bool) {
        let base = NowPlayingAttributes.playlist[index]
        var words = labels[index] ?? Labels()
        if title { words.title = text == base.title ? nil : text }
        else { words.artist = text == base.artist ? nil : text }
        labels[index] = words.title == nil && words.artist == nil ? nil : words
    }

    struct InputError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func check(_ value: Double?, name: String, positive: Bool = false) throws {
        guard let value else { return }
        guard value.isFinite, positive ? value > 0 : value >= 0 else {
            throw InputError("\(name)には\(positive ? "0より大きい" : "0以上の")有限の数を入力してください。")
        }
    }

    func validate() throws {
        try Self.check(speed, name: "速度")
        if synchronized, speed == nil { throw InputError("同期する行に共通の速度を入力してください。") }
        try Self.check(pause, name: "周回の待ち時間")
        try Self.check(spacing, name: "周回の余白")
        try Self.check(fade, name: "フェードの長さ")
        try Self.check(clearance, name: "フェードからの余白")
        try motion.validate()
        try titleRow.validate()
        try artistRow.validate()
        for index in NowPlayingAttributes.playlist.indices {
            let track = track(index)
            guard !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InputError("\(index + 1)曲目の曲名とアーティスト名を入力してください。")
            }
        }
    }
}

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
        var playingFrom: Date?
        var pausedAt: TimeInterval = 0
        // Cards created before the settings editor have no settings field.
        var settings: PlayerSettings?

        var configuration: PlayerSettings { settings ?? PlayerSettings() }
        var track: Track { configuration.track(trackIndex) }

        mutating func selectTrack(_ index: Int, at now: Date) {
            guard index != trackIndex else { return }
            trackIndex = index
            titleStartedAt = now
            if playingFrom != nil { playingFrom = now }
            pausedAt = 0
        }

        mutating func configure(_ value: PlayerSettings, track index: Int, at now: Date) {
            if value != configuration { titleStartedAt = now }
            settings = value == PlayerSettings() ? nil : value
            selectTrack(index, at: now)
        }

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
                selectTrack((trackIndex + playlist.count + step) % playlist.count, at: now)
            }
        }
    }

    static func validate(_ state: ContentState) throws {
        guard playlist.indices.contains(state.trackIndex) else {
            throw PlayerSettings.InputError("プレイリストの曲を選び直してください。")
        }
        try state.configuration.validate()
        let encoder = JSONEncoder()
        let byteCount = try encoder.encode(Self()).count + encoder.encode(state).count
        guard byteCount <= 4_096 else {
            throw PlayerSettings.InputError("カードのデータは\(byteCount)バイトです。4,096バイト以内になるように曲名やアーティスト名を短くしてください。")
        }
    }

    /// Start the sample card from a foreground app.
    @discardableResult
    static func start(settings: PlayerSettings = PlayerSettings(), track: Int = 0) throws -> Activity<Self> {
        let now = Date.now
        var state = ContentState(titleStartedAt: now, playingFrom: now)
        state.configure(settings, track: track, at: now)
        try validate(state)
        return try Activity.request(attributes: Self(), content: .init(state: state, staleDate: nil), pushType: nil)
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
            try NowPlayingAttributes.validate(state)
            await activity.update(.init(state: state, staleDate: nil))
        }
        return .result()
    }
}

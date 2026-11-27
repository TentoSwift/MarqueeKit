import ActivityKit
import SwiftUI
import UIKit

// Use as the @main entry point of the sample app target.
@main
struct MarqueePlayerApp: App {
    var body: some Scene { WindowGroup { PlayerScreen() } }
}

private struct PlayerScreen: View {
    private static let settingsKey = "MarqueePlayer.settings.v1"
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("MarqueePlayer.track") private var selectedTrack = 0
    @State private var settings: PlayerSettings
    @State private var activity: Activity<NowPlayingAttributes>?
    @State private var observedTrack: Int?
    @State private var busy = false
    @State private var usedLaunchArgument = false
    @State private var errorMessage = ""
    @State private var applied = false
    @State private var resetRequested = false

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.settingsKey)
        _settings = State(initialValue: saved.flatMap { try? JSONDecoder().decode(PlayerSettings.self, from: $0) } ?? .init())
    }

    private var activeCards: [Activity<NowPlayingAttributes>] {
        Activity<NowPlayingAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(activity == nil ? "カードは停止中" : "カードを表示中",
                          systemImage: activity == nil ? "pause.circle" : "waveform")
                    if activity == nil {
                        Button("再生カードを開始", action: start)
                    } else {
                        Button(applied ? "カードに反映しました" : "変更をカードに反映") { Task { await update() } }
                        Button("再生カードを終了", role: .destructive) { Task { await end() } }
                    }
                } footer: {
                    Text("ロック画面や通知センターを開くか、Dynamic Islandを長押ししてカードを確認できます。")
                }
                .disabled(busy)
                if !errorMessage.isEmpty {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section("曲") {
                    Picker("編集する曲", selection: $selectedTrack) {
                        ForEach(NowPlayingAttributes.playlist.indices, id: \.self) { index in
                            Text("\(index + 1)曲目").tag(index)
                        }
                    }
                    TextField("曲名", text: textBinding(title: true), axis: .vertical)
                        .accessibilityLabel("曲名")
                    TextField("アーティスト名", text: textBinding(title: false), axis: .vertical)
                        .accessibilityLabel("アーティスト名")
                }
                Section("スクロール") {
                    Picker("向き", selection: $settings.direction) {
                        Text("横送り").tag(PlayerSettings.Direction.horizontal)
                        Text("縦送り").tag(PlayerSettings.Direction.vertical)
                    }
                    Toggle("全行が終わってから一緒に再開", isOn: $settings.synchronized)
                    if settings.synchronized {
                        NumberSetting("速度", value: required($settings.speed, fallback: 28), unit: "pt/秒")
                    } else {
                        OptionalNumberSetting("速度を指定", label: "速度", value: $settings.speed,
                                              fallback: 28, unit: "pt/秒")
                    }
                    MotionSettings(motion: $settings.motion)
                    NumberSetting("次の周回まで", value: $settings.pause, unit: "秒")
                    OptionalNumberSetting("周回の余白を指定", label: "末尾と次の先頭の余白",
                                          value: $settings.spacing, fallback: 24, unit: "pt")
                }
                Section("端のフェード") {
                    NumberSetting("フェードの長さ", value: $settings.fade, unit: "pt")
                    NumberSetting("フェードと先頭文字の余白", value: $settings.clearance, unit: "pt")
                }
                Section("行ごとの設定") {
                    NavigationLink("曲名の設定") { RowSettings(row: $settings.titleRow, name: "曲名", common: settings) }
                    NavigationLink("アーティスト名の設定") {
                        RowSettings(row: $settings.artistRow, name: "アーティスト名", common: settings)
                    }
                }
                Section {
                    NavigationLink("Swiftコードを表示・コピー") { PlayerCodeView(settings: settings, track: currentIndex) }
                    Button("設定を初期値に戻す", role: .destructive) { resetRequested = true }
                } footer: {
                    Text("編集内容はこの端末に保存されます。表示中のカードには「変更をカードに反映」で適用します。")
                }
            }
            .navigationTitle("Marquee Player")
            .confirmationDialog("すべての曲と設定を初期値に戻しますか？", isPresented: $resetRequested, titleVisibility: .visible) {
                Button("初期値に戻す", role: .destructive) {
                    settings = .init()
                    selectedTrack = 0
                    errorMessage = ""
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .onChange(of: settings) { _, value in
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
            errorMessage = ""
            applied = false
        }
        .onChange(of: selectedTrack) { _, _ in applied = false }
        .onChange(of: settings.synchronized) { _, synced in
            if synced && settings.speed == nil { settings.speed = 28 }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            let current = activeCards.first
            if let current, activity?.id != current.id || selectedTrack == observedTrack {
                selectedTrack = current.content.state.trackIndex
            }
            observedTrack = current?.content.state.trackIndex
            activity = current
            guard !usedLaunchArgument, ProcessInfo.processInfo.arguments.contains("--start-player") else { return }
            usedLaunchArgument = true
            Task { @MainActor in
                if ProcessInfo.processInfo.arguments.contains("--fresh-sample") { await end() }
                start()
            }
        }
        .task(id: activity?.id) {
            guard let card = activity else { return }
            for await state in card.activityStateUpdates {
                guard !Task.isCancelled, activity?.id == card.id else { return }
                if state == .ended || state == .dismissed {
                    activity = activeCards.first
                    return
                }
            }
        }
        .task(id: activity?.id) {
            guard let card = activity else { return }
            for await content in card.contentUpdates {
                guard !Task.isCancelled, activity?.id == card.id else { return }
                if selectedTrack == observedTrack { selectedTrack = content.state.trackIndex }
                observedTrack = content.state.trackIndex
            }
        }
    }

    private var currentIndex: Int { NowPlayingAttributes.playlist.indices.contains(selectedTrack) ? selectedTrack : 0 }

    private func textBinding(title: Bool) -> Binding<String> {
        Binding {
            let track = settings.track(currentIndex)
            return title ? track.title : track.artist
        } set: { settings.setText($0, for: currentIndex, title: title) }
    }

    private func start() {
        errorMessage = ""
        applied = false
        if let existing = activeCards.first {
            activity = existing
            observedTrack = existing.content.state.trackIndex
            report("existing id=" + existing.id)
            return
        }
        do {
            let card = try NowPlayingAttributes.start(settings: settings, track: currentIndex)
            activity = card
            observedTrack = card.content.state.trackIndex
            report("started id=" + card.id + " state=" + String(describing: card.activityState))
        } catch { show(error) }
    }

    @MainActor private func update() async {
        guard !busy, let card = activeCards.first else { return }
        busy = true
        defer { busy = false }
        do {
            var state = card.content.state
            state.configure(settings, track: currentIndex, at: .now)
            try NowPlayingAttributes.validate(state)
            await card.update(.init(state: state, staleDate: nil))
            errorMessage = ""
            applied = true
            UIAccessibility.post(notification: .announcement, argument: "カードに反映しました")
        } catch { show(error) }
    }

    @MainActor private func end() async {
        busy = true
        for card in activeCards { await card.end(nil, dismissalPolicy: .immediate) }
        activity = activeCards.first
        observedTrack = activity?.content.state.trackIndex
        busy = false
        errorMessage = ""
        applied = false
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        UIAccessibility.post(notification: .announcement, argument: errorMessage)
        report("error " + errorMessage)
    }

    private func report(_ message: String) {
        guard ProcessInfo.processInfo.arguments.contains("--start-player") else { return }
        let line = "MARQUEE_PLAYER " + message + "\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? line.write(to: documents.appendingPathComponent("player-status.txt"), atomically: true, encoding: .utf8)
        }
    }
}

private func required<T>(_ value: Binding<T?>, fallback: T) -> Binding<T> {
    Binding(get: { value.wrappedValue ?? fallback }, set: { value.wrappedValue = $0 })
}

private struct MotionSettings: View {
    @Binding var motion: PlayerMotion

    var body: some View {
        Picker("動き方", selection: $motion.style) {
            ForEach(PlayerMotion.Style.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if motion.style == .custom {
            NumberSetting("加速時間", value: $motion.acceleration, unit: "秒")
            curvePicker("加速の曲線", selection: $motion.accelerationCurve)
            NumberSetting("減速時間", value: $motion.deceleration, unit: "秒")
            curvePicker("減速の曲線", selection: $motion.decelerationCurve)
            Text("指定した速度は、加速後から減速前までの巡航速度です。").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func curvePicker(_ label: String, selection: Binding<PlayerCurve>) -> some View {
        Picker(label, selection: selection) {
            ForEach(PlayerCurve.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
        }
    }
}

private struct RowSettings: View {
    @Binding var row: PlayerRow
    let name: String
    let common: PlayerSettings

    var body: some View {
        Form {
            Section("共通設定の上書き") {
                OptionalNumberSetting("行の速度を指定", label: "行の速度", value: $row.speed,
                                      fallback: common.speed ?? 28, unit: "pt/秒")
                OptionalNumberSetting("行の余白を指定", label: "行の余白", value: $row.spacing,
                                      fallback: common.spacing ?? 24, unit: "pt")
                Toggle("行の動き方を指定", isOn: Binding(get: { row.motion != nil }, set: {
                    row.motion = $0 ? common.motion : nil
                }))
                if row.motion != nil { MotionSettings(motion: required($row.motion, fallback: common.motion)) }
            }
            Section {
                NumberSetting("文字サイズ", value: $row.fontSize, unit: "pt", positive: true)
                Picker("システムフォントの太さ", selection: $row.weight) {
                    ForEach(PlayerRow.Weight.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("任意のフォントのPostScript名", text: $row.fontName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("横送りのフォント") } footer: {
                Text("フォント名を空にすると、指定した太さのシステムフォントを使います。縦送りは1文字ずつ同じ高さに収めます。")
            }
        }
        .navigationTitle(name + "の設定")
    }
}

private struct OptionalNumberSetting: View {
    let toggle: String
    let label: String
    @Binding var value: Double?
    let fallback: Double
    let unit: String

    init(_ toggle: String, label: String, value: Binding<Double?>, fallback: Double, unit: String) {
        self.toggle = toggle
        self.label = label
        _value = value
        self.fallback = fallback
        self.unit = unit
    }

    var body: some View {
        Toggle(toggle, isOn: Binding(get: { value != nil }, set: { value = $0 ? fallback : nil }))
        if value != nil { NumberSetting(label, value: required($value, fallback: fallback), unit: unit) }
    }
}

private struct NumberSetting: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let positive: Bool
    @State private var editing = false
    @State private var input = ""
    @State private var error = ""

    init(_ label: String, value: Binding<Double>, unit: String, positive: Bool = false) {
        self.label = label
        _value = value
        self.unit = unit
        self.positive = positive
    }

    var body: some View {
        Button {
            input = String(value)
            error = ""
            editing = true
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.formatted()) \(unit)").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    TextField("\(label)（\(unit)）", text: $input).keyboardType(.numbersAndPunctuation)
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle(label)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func save() {
        let decimal = Locale.current.decimalSeparator ?? "."
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: decimal, with: ".")
        guard let number = Double(text), number.isFinite, positive ? number > 0 : number >= 0 else {
            error = positive ? "0より大きい数を入力してください。" : "0以上の数を入力してください。"
            return
        }
        value = number
        editing = false
    }
}

private struct PlayerCodeView: View {
    let settings: PlayerSettings
    let track: Int
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading) {
            if let error = validationError { Text(error).foregroundStyle(.red).padding() }
            else {
                let source = MarqueePlayerCode.make(settings: settings, track: track)
                Button {
                    UIPasteboard.general.string = source
                    copied = true
                    UIAccessibility.post(notification: .announcement, argument: "Swiftコードをコピーしました")
                } label: {
                    Label(copied ? "コピーしました" : "Swiftコードをコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                ScrollView([.horizontal, .vertical]) {
                    Text(verbatim: source).font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled).padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Swiftコード")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var validationError: String? {
        do { try settings.validate(); return nil }
        catch { return error.localizedDescription }
    }
}

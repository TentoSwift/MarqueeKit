# MarqueeKit

iOSアプリ、ホーム画面Widget、Live Activityで、1行に収まらない文字列を左に送り、末尾から先頭に戻って繰り返すSwift Packageです。好きな `String` を渡すと、その文章の長さに合わせて表示位置を決めます。iOS 17以降、Swift tools 5.9以降に対応しています。

![ホーム画面で位置が12から1に戻り、ENDの後にSTARTが続く様子を2周分撮影](Documentation/loop.png)

## インストール

Xcodeの **File → Add Package Dependencies…** で `https://github.com/TentoSwift/MarqueeKit.git` を指定し、バージョン `1.5.0` 以降を選びます。製品 `MarqueeKit` は、表示するアプリまたはWidget Extensionのターゲットに追加します。

`Package.swift` から追加する場合は、`dependencies` に次の行を指定します。

```swift
.package(url: "https://github.com/TentoSwift/MarqueeKit.git", from: "1.5.0")
```

利用するターゲットの `dependencies` にも製品を追加します。

```swift
.product(name: "MarqueeKit", package: "MarqueeKit")
```

1.5.0でパッケージ名とリポジトリ名を `WidgetMarquee` から `MarqueeKit` に変更しました。既存プロジェクトを移行するには、依存先URLと製品の指定を上記に合わせ、ソースのインポートを `import MarqueeKit` に変更します。`WidgetMarquee(text)` や `LiveActivityMarquee(text, startedAt:)` は引き続き同じ名前で使えます。従来の `import WidgetMarquee` を使うターゲットには、互換用の製品 `WidgetMarquee` を指定できます。

## SwiftUIアプリで使う

ビューに文字列を渡すと、自動で進みます。`text` には画面で入力した値やモデルから取得した値も渡せます。

```swift
import SwiftUI
import MarqueeKit

struct MessageView: View {
    let text: String

    var body: some View {
        WidgetMarquee(text)
    }
}
```

## スクロールの速度、加減速、周回の待ち時間

`pointsPerSecond` は移動中の平均速度で、単位は画面上のポイント毎秒です。単独の行に `.easeInOut` を指定すると、各周の始めと終わりでゆっくり動き、中央で最も速くなります。一周して文章の先頭に戻ると、`pauseBetweenLoops` に指定した秒数だけその位置で待ちます。

```swift
// SwiftUIアプリ
WidgetMarquee(text, pointsPerSecond: 40, timing: .easeInOut, pauseBetweenLoops: 2)

// ホーム画面Widgetのプロバイダ
WidgetMarquee.timeline(for: text, pointsPerSecond: 40, timing: .easeInOut, pauseBetweenLoops: 2)

// Live Activity
LiveActivityMarquee(text, startedAt: startedAt, pointsPerSecond: 40,
                    timing: .easeInOut, pauseBetweenLoops: 2)
```

iOS 27.2シミュレータのLive Activityでは、同じ文章に30、60 pt/秒を指定して、約30、60 pt/秒で移動したことを確認しました。90 pt/秒・2秒待機の設定では、等速の行は約5.7秒で移動し、約2秒静止しました。緩急を付けた行は同じ周期で、中央で約135 pt/秒まで加速しました。[加減速と2秒待機の録画（MP4）](https://github.com/TentoSwift/MarqueeKit/releases/download/1.3.0/live-activity-ease-and-pause.mp4)

各引数は個別に省略できます。既定は等速（`.linear`）で、周回の待ち時間は0秒です。速度を省略するとLive Activityは10秒で一周し、SwiftUIアプリとホーム画面Widgetは文章の長さに応じた従来の周期を使います。たとえばLive Activityに `pauseBetweenLoops: 2` だけを渡すと、10秒かけて移動して2秒待ちます。速度0、負の速度、非有限の速度では文章が静止します。負の待ち時間や非有限の待ち時間は0秒として扱います。

## 複数の行が終わってから一緒に再開する

`WidgetMarqueeGroup` に同時に再開したい文章をまとめます。各行は自分の速度で一周し、先に終わった行は先頭位置で待ちます。最後の行が戻った時点から `pauseBetweenLoops` 秒後に全行が再開します。待ち時間が0なら最後の行が戻った時点で再開します。[長さの違う2行を同期させた録画（MP4）](https://github.com/TentoSwift/MarqueeKit/releases/download/1.4.0/synchronized-marquees.mp4)

```swift
let group = WidgetMarqueeGroup(
    [title, subtitle], startedAt: context.attributes.startedAt,
    pointsPerSecond: 40, timing: .easeInOut, pauseBetweenLoops: 2
)

VStack(alignment: .leading) {
    ForEach(group.rows) { row in LiveActivityMarquee(row) }
}
```

SwiftUIアプリでは同じ `group.rows` を `WidgetMarquee(row)` に渡します。`startedAt` にはアプリの状態に保存した開始日時、またはLive Activityの開始属性を使い、ビューを描き直しても同じ日時を渡してください。別々に周回させる場合は、従来どおり文章を各ビューに直接渡します。

長さの異なる2行に同じ `pointsPerSecond` と `.easeInOut` を指定すると、一緒に加速して同じ巡航速度に達します。その後は各行が自分の終点に近づいたときだけ減速します。短い行が先頭で待っている間も、長い行はそのまま進みます。`pointsPerSecond` は一周の移動中の平均速度なので、加減速のある行の巡航速度は指定値より少し速くなります。`.linear` では指定した速度のまま一周します。[短い行の停止前後を収めた録画（MP4）](https://github.com/TentoSwift/MarqueeKit/releases/download/1.4.2/independent-marquee-stops.mp4)

表示幅に収まる行がある場合は、`viewportWidth` にラベルや余白を除いた本文の幅を渡してください。グループはその行を加減速と待ち時間の計算から除外します。行ごとに速度や表示幅が異なる場合は `items:` を使えます。速度0の行もほかの行を待たせません。

```swift
let group = WidgetMarqueeGroup(items: [
    .init(title, pointsPerSecond: 30, viewportWidth: titleWidth),
    .init(subtitle, viewportWidth: subtitleWidth)
], startedAt: startedAt, pointsPerSecond: 50, pauseBetweenLoops: 2)
```

ホーム画面Widgetでは、プロバイダのエントリ型を `WidgetMarqueeGroupEntry` にし、`timeline` で `group.timeline()` を返します。`placeholder` と `snapshot` には `WidgetMarqueeGroupEntry(group)` を使います。同じエントリに全行の表示位置が入るので、Widgetのビューで次のように並べられます。再読み込み時にも同じ開始日時を使います。

```swift
VStack(alignment: .leading) {
    ForEach(entry.rows.indices, id: \.self) { index in
        WidgetMarquee(entry.rows[index])
    }
}
```

## ホーム画面Widgetで使う

プロバイダから `WidgetMarquee.timeline(for:)` を返します。各エントリには文章、表示日時、スクロールの設定が入ります。`placeholder` と `snapshot` には `WidgetMarqueeEntry("見本の文章")` を返せます。

```swift
// AppIntentTimelineProvider のメソッド
func timeline(for configuration: HeadlineConfiguration, in context: Context) async -> Timeline<WidgetMarqueeEntry> {
    WidgetMarquee.timeline(for: configuration.headline)
}
```

Widgetのビューにはそのエントリを渡します。

```swift
WidgetMarquee(entry)
    .containerBackground(.background, for: .widget)
```

独自の `TimelineEntry` を使っている場合は、これまでどおり `WidgetMarquee(entry.headline, date: entry.date, schedule: schedule)` と `schedule.timeline(from:entry:)` を組み合わせられます。

### ホーム画面から文章を編集するサンプル

1. [HeadlineWidget.swift](Examples/HeadlineWidget.swift) をWidget Extensionターゲットに追加し、テンプレートの `@main` をこのサンプルに置き換えます。
2. アプリを実行し、iPhoneのホーム画面に中サイズの「Headline」を追加します。
3. Widgetを長押しして「ウィジェットを編集」を開き、「テキスト」に好きな文章を入力します。編集を閉じると、その文章で表示が始まります。

文章はWidgetごとに設定できます。空欄や空白だけの入力には見本の文章を表示します。1行に収まる短い文章は静止し、長い文章は自動で横に流れます。

「視差効果を減らす」が有効な場合や画面の輝度が下がった場合は、先頭を静止表示します。VoiceOverは文章全体を1回で読み上げます。

## Live Activityで使う

ロック画面と展開中のDynamic Islandでは `LiveActivityMarquee` に文章と開始日時を渡します。開始日時はアクティビティの属性に保持します。

1.4.3では、文字送りに使うフォントを小さくしました。同期した2行を表示すると、Dynamic Island用の描画データがサイズ上限を超え、開始直後にLive Activityが終了することがあったためです。APIと呼び出し方はこれまでと同じです。

```swift
import MarqueeKit

// ActivityConfiguration の Lock Screen ビューまたは DynamicIslandExpandedRegion 内
LiveActivityMarquee(context.state.text, startedAt: context.attributes.startedAt)
```

iOS 18以降では、アプリがバックグラウンドにあっても長い文章が自動で流れます。速度指定を省略した場合の移動時間は約10秒です。OSが描画するストップウォッチと本文を1行に並べ、経過時間に応じて先頭の透明な文字の幅を縮める仕組みです。フォントはパッケージに同梱しており、文字送りのためのタイマー、プッシュ通知、`Activity.update` は不要です。[SwiftUIのストップウォッチ](https://developer.apple.com/documentation/swiftui/systemformatstyle/stopwatch)

iOS 17、またはiOS 17 SDKでビルドした場合は、約1秒ごとに位置を更新します。どちらも1行に収まる文章は静止し、「視差効果を減らす」が有効なときや、常時表示で輝度が下がったときも静止表示に切り替わります。VoiceOverは元の文章を1回で読み上げます。

iPhone 17 Proシミュレータ（iOS 27.2）で日本語の文章を表示し、点灯中のロック画面で毎秒約51回、展開中のDynamic Islandで毎秒約50回、本文の位置が変わることを確認しました。下の録画は、等速で自動スクロールする行を切り出したものです。1.3.0では時計の分表示が変わる瞬間に起きていた逆向きの動きを修正しました。

![ロック画面のLive Activityで「自動」行の日本語が左へ流れて一周する様子](Documentation/live-activity-smooth.gif)

AppleのFrameworks Engineerは、タイマーとカスタムフォントを使うアニメーションをサポート対象外としており、電池や性能への影響を指摘しています。実際の更新頻度はOSや表示状態に左右されます。Live Activityで加減速、待機、複数行の同期を指定すると一周を4,096段階で表すため、文章や待ち時間が非常に長いと、文字送りの刻みが目立つことがあります。グループの加減速は共通の時刻で移動距離を補間するため、画面上で各行が止まる時刻には丸めが入ります。[Appleの技術者による説明](https://developer.apple.com/forums/thread/757696)

### サンプルを実行する

1. アプリのInfo.plistで `NSSupportsLiveActivities` を有効にします。
2. [MarqueeActivityAttributes.swift](Examples/MarqueeLiveActivity/MarqueeActivityAttributes.swift) をアプリとWidget Extensionの両方に、[MarqueeLiveActivity.swift](Examples/MarqueeLiveActivity/MarqueeLiveActivity.swift) を拡張に追加します。
3. 拡張の `@main WidgetBundle` の `body` に `MarqueeLiveActivity()` を追加します。

アプリがフォアグラウンドにあるときに開始します。たとえば次の関数に任意の文章を渡せます。

```swift
import ActivityKit
import Foundation

func startMarquee(_ message: String) throws -> Activity<MarqueeActivityAttributes> {
    let attributes = MarqueeActivityAttributes(startedAt: .now)
    return try Activity.request(
        attributes: attributes,
        content: try attributes.content(for: message, pointsPerSecond: 40),
        pushType: nil
    )
}
```

別の文章や速度に差し替えるときは `await activity.update(try activity.attributes.content(for: newText, pointsPerSecond: 60))`、終了時は `await activity.end(nil, dismissalPolicy: .immediate)` を使います。サンプルは送信前に、属性と状態の合計がActivityKitの4 KB制限に収まるか確認します。自動ループが続くのはLive Activityの動作中で、1回のアクティビティは最長8時間です。[AppleのLive Activity仕様](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

ActivityKitのデータ更新に合わせて1段だけ送る場合は、状態に表示位置の日時を持たせ、`WidgetMarquee(text, date: positionDate)` に渡せます。iPhone Duo（iOS 27.3）では、経過タイマーだけが8秒進んだ間は文字位置が同じで、更新を1件送ると位置が変わりました。[シミュレータでの比較画像](Documentation/live-activity.png)

## ホーム画面Widgetの周期と更新

2秒ごとに次の表示位置を使います。自動設定では最低12段階で一周し、長い文章では段階数を増やします。一周の時間を調整するには、`let pace = WidgetMarqueeSchedule(stepsPerPass: 30)` のように設定を作り、アプリでは `WidgetMarquee(text, schedule: pace)`、Widgetでは `WidgetMarquee.timeline(for: text, schedule: pace)` に渡します。30段階なら一周は約60秒です。指定できる範囲は2〜3,600段階です。

既定のスケジュールは5分ぶんの151エントリをまとめて返し、4分後の再読み込みをWidgetKitに依頼します。各位置は絶対時刻に対応するため、次のタイムラインでも続きから表示できます。iOS 27.2のiPhone 17 Proシミュレータでは、操作せずに複数回折り返し、最初の5分を超えても次のタイムラインで更新が続くことを確認しました。

**2秒間隔は実験用の設定です。** Appleの推奨するエントリ間隔の目安は約5分以上です。OSは更新をまとめたり遅らせたりするため、コマ送りになることがあり、予定を使い切ると次の読み込みまで最後の位置で待ちます。上の画像と検証記録の対象はホーム画面Widgetです。実機での電力消費や長時間の更新間隔は未計測です。[WidgetKitの更新仕様](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)

## ライセンス

[MIT License](LICENSE)

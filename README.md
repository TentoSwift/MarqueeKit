# WidgetMarquee

iOSアプリとホーム画面Widgetで、1行に収まらない文字列を左に送り、末尾から先頭に戻って繰り返すSwift Packageです。好きな `String` を渡すと、その文章の長さに合わせて表示位置を決めます。iOS 17以降、Swift tools 5.9以降に対応しています。

![ホーム画面で位置が12から1に戻り、ENDの後にSTARTが続く様子を2周分撮影](Documentation/loop.png)

## インストール

Xcodeの **File → Add Package Dependencies…** で `https://github.com/TentoSwift/WidgetMarquee.git` を指定し、バージョン `1.1.0` 以降を選びます。製品 `WidgetMarquee` は、表示するアプリまたはWidget Extensionのターゲットに追加します。

`Package.swift` から追加する場合は、`dependencies` に次の行を指定します。

```swift
.package(url: "https://github.com/TentoSwift/WidgetMarquee.git", from: "1.1.0")
```

## SwiftUIアプリで使う

ビューに文字列を渡すと、自動で進みます。`text` には画面で入力した値やモデルから取得した値も渡せます。

```swift
import SwiftUI
import WidgetMarquee

struct MessageView: View {
    let text: String

    var body: some View {
        WidgetMarquee(text)
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

## 周期と更新

2秒ごとに次の表示位置を使います。自動設定では最低12段階で一周し、長い文章では段階数を増やします。一周の時間を調整するには、`let pace = WidgetMarqueeSchedule(stepsPerPass: 30)` のように設定を作り、アプリでは `WidgetMarquee(text, schedule: pace)`、Widgetでは `WidgetMarquee.timeline(for: text, schedule: pace)` に渡します。30段階なら一周は約60秒です。指定できる範囲は2〜3,600段階です。

スケジュールは5分ぶんの151エントリをまとめて返し、4分後の再読み込みをWidgetKitに依頼します。各位置は絶対時刻に対応するため、次のタイムラインでも続きから表示できます。iOS 27.2のiPhone 17 Proシミュレータでは、操作せずに複数回折り返し、最初の5分を超えても次のタイムラインで更新が続くことを確認しました。

**2秒間隔は実験用の設定です。** Appleの推奨するエントリ間隔の目安は約5分以上です。OSは更新をまとめたり遅らせたりするため、コマ送りになることがあり、予定を使い切ると次の読み込みまで最後の位置で待ちます。上の画像と検証記録の対象はホーム画面Widgetです。実機での電力消費や長時間の更新間隔は未計測です。[WidgetKitの更新仕様](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)

## ライセンス

[MIT License](LICENSE)

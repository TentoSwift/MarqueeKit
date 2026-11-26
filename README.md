# WidgetMarquee

iPhoneのホーム画面Widgetで、1行に収まらない文字列を自動で左に送り、末尾から先頭に戻って繰り返すSwift Packageです。ホーム画面にWidgetを追加するだけで動きます。SwiftUIとWidgetKitの公開APIを使用します。対応はiOS 17以降、Swift tools 5.9以降です。

![ホーム画面で位置が12から1に戻り、ENDの後にSTARTが続く様子を2周分撮影](Documentation/loop.png)

## インストール

Xcodeの **File → Add Package Dependencies…** で `https://github.com/TentoSwift/WidgetMarquee.git` を指定し、バージョン `1.0.0` 以降の製品 `WidgetMarquee` をWidget Extensionターゲットに追加します。

`Package.swift` から追加する場合は、`dependencies` に次の行を指定します。

```swift
.package(url: "https://github.com/TentoSwift/WidgetMarquee.git", from: "1.0.0")
```

## 組み込み

タイムラインプロバイダとビューで同じスケジュールを使います。既存の `TimelineEntry` に、クロージャが受け取った日時をそのまま保存してください。

```swift
import SwiftUI
import WidgetKit
import WidgetMarquee

private let schedule = WidgetMarqueeSchedule()

// TimelineProvider のメソッド。headline はプロバイダが読み込んだ見出し。
func getTimeline(in context: Context, completion: @escaping (Timeline<HeadlineEntry>) -> Void) {
    completion(schedule.timeline(from: .now) { date in
        HeadlineEntry(date: date, headline: headline)
    })
}
```

Widgetのビューにエントリの日時を渡すと、その時点の表示位置が決まります。1行に収まる文章、「視差効果を減らす」が有効な場合、画面の輝度が下がった場合は、先頭を静止表示します。VoiceOverは文章全体を1回で読み上げます。

```swift
WidgetMarquee(entry.headline, date: entry.date, schedule: schedule)
    .containerBackground(.background, for: .widget)
```

プロバイダからWidgetの宣言までを含む例を用意しています。新しいWidget Extensionで試す場合は、テンプレートの `@main` をこの例のものに置き換え、ホーム画面に中サイズの「Headline」を追加してください。[最小のWidget実装](Examples/HeadlineWidget.swift)

## 周期と更新

既定では2秒ごとに12の表示位置を順に使い、約24秒で一周します。`stepsPerPass` には2〜3,600を指定できます。たとえば `WidgetMarqueeSchedule(stepsPerPass: 30)` にすると、一周は約60秒です。長い文字列では、1回の移動距離が表示幅を超えないように段階数を増やすと、途中の文字も読めます。`schedule.phase(at: entry.date)` は現在位置を0始まりで返します。

スケジュールは5分ぶんの151エントリをまとめて返し、4分後の再読み込みをWidgetKitに依頼します。各位置は絶対時刻に対応するため、次のタイムラインでも続きから表示できます。iOS 27.2のiPhone 17 Proシミュレータでは、操作せずに複数回折り返し、最初の5分を超えても次のタイムラインで更新が続くことを確認しました。

**2秒間隔は実験用の設定です。** Appleの推奨するエントリ間隔の目安は約5分以上です。OSは更新をまとめたり遅らせたりするため、コマ送りになることがあり、予定を使い切ると次の読み込みまで最後の位置で待ちます。上の画像と検証記録の対象はホーム画面Widgetです。実機での電力消費や長時間の更新間隔は未計測です。[WidgetKitの更新仕様](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)

## ライセンス

[MIT License](LICENSE)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WidgetMarquee",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WidgetMarquee", targets: ["WidgetMarquee"])
    ],
    targets: [
        .target(
            name: "WidgetMarquee",
            resources: [
                .copy("Resources/WidgetMarqueeStopwatch.ttf"),
                .copy("Resources/WidgetMarqueeSpeed.ttf"),
                .copy("Resources/WidgetMarqueePlayback.ttf"),
                .copy("Resources/WidgetMarqueeTimerGate.ttf")
            ]
        ),
        .testTarget(name: "WidgetMarqueeTests", dependencies: ["WidgetMarquee"])
    ]
)

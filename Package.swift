// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarqueeKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MarqueeKit", targets: ["MarqueeKit"]),
        .library(name: "WidgetMarquee", targets: ["WidgetMarquee"])
    ],
    targets: [
        .target(
            name: "MarqueeKit",
            resources: [
                .copy("Resources/WidgetMarqueeStopwatch.ttf"),
                .copy("Resources/WidgetMarqueeSpeed.ttf"),
                .copy("Resources/WidgetMarqueePlayback.ttf"),
                .copy("Resources/WidgetMarqueeTimerGate.ttf")
            ]
        ),
        .target(name: "WidgetMarquee", dependencies: ["MarqueeKit"]),
        .testTarget(name: "MarqueeKitTests", dependencies: ["MarqueeKit"])
    ]
)

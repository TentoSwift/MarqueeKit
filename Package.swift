// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WidgetMarquee",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WidgetMarquee", targets: ["WidgetMarquee"])
    ],
    targets: [
        .target(name: "WidgetMarquee"),
        .testTarget(name: "WidgetMarqueeTests", dependencies: ["WidgetMarquee"])
    ]
)

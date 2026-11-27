import Foundation

// Add to the app target. The copied view uses only public MarqueeKit APIs.
enum MarqueePlayerCode {
    static func make(settings: PlayerSettings, track index: Int) -> String {
        let track = settings.track(index)
        let rows = [(track.title, settings.titleRow), (track.artist, settings.artistRow)]
        let vertical = settings.direction == .vertical
        let stack = vertical ? "HStack(alignment: .top, spacing: 8)" : "VStack(alignment: .leading, spacing: 0)"
        let axis = "." + settings.direction.rawValue
        var lines = [
            "import MarqueeKit", "import SwiftUI", "import UIKit", "",
            "struct PlayerMarquees: View {", "    let startedAt: Date", "    var height: CGFloat = 57", "",
            "    var body: some View {", "        GeometryReader { area in"
        ]
        if settings.synchronized {
            let length = vertical ? "area.size.height" : "area.size.width"
            lines.append("            let group = WidgetMarqueeGroup(items: [")
            for (index, pair) in rows.enumerated() {
                let (text, row) = pair
                lines += [
                    "                .init(\(literal(text)), pointsPerSecond: \(number(row.speed)),",
                    "                      timing: \(row.motion.map(timing) ?? "nil"), viewportLength: \(length),",
                    "                      horizontalFont: \(font(row)),",
                    "                      repeatSpacing: \(number(row.spacing)), ramps: \(ramps(row.motion)))\(index == 0 ? "," : "")"
                ]
            }
            lines += [
                "            ], startedAt: startedAt, pointsPerSecond: \(number(settings.speed ?? 28)),",
                "               timing: \(timing(settings.motion)), pauseBetweenLoops: \(number(settings.pause)),",
                "               axis: \(axis), repeatSpacing: \(number(settings.spacing)), ramps: \(ramps(settings.motion)))",
                "            \(stack) {", "                ForEach(group.rows) { row in",
                "                    LiveActivityMarquee(row)",
                "                        .foregroundStyle(row.id == 0 ? Color.white : Color.white.opacity(0.55))",
                "                }"
            ]
        } else {
            lines.append("            \(stack) {")
            for (index, pair) in rows.enumerated() {
                let (text, row) = pair
                let motion = row.motion ?? settings.motion
                lines += [
                    "                LiveActivityMarquee(\(literal(text)), startedAt: startedAt,",
                    "                    pointsPerSecond: \(number(row.speed ?? settings.speed)), timing: \(timing(motion)),",
                    "                    pauseBetweenLoops: \(number(settings.pause)), axis: \(axis),",
                    "                    horizontalFont: \(font(row)), repeatSpacing: \(number(row.spacing ?? settings.spacing)),",
                    "                    ramps: \(ramps(motion)))",
                    "                    .foregroundStyle(\(index == 0 ? "Color.white" : "Color.white.opacity(0.55)"))"
                ]
            }
        }
        lines += [
            "            }", "            .marqueeEdgeFade(length: \(number(settings.fade)), clearance: \(number(settings.clearance)))",
            "            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)",
            "        }", "        .frame(height: height)", "    }", "}", "",
            "// Live Activityのビューで開始日時を渡します。", "// PlayerMarquees(startedAt: context.state.titleStartedAt)"
        ]
        return lines.joined(separator: "\n")
    }

    private static func number(_ value: Double?) -> String {
        value.map { String($0) } ?? "nil"
    }

    private static func font(_ row: PlayerRow) -> String {
        let system = "UIFont.systemFont(ofSize: \(number(row.fontSize)), weight: .\(row.weight.rawValue))"
        if row.fontName.isEmpty { return system }
        return "UIFont(name: \(literal(row.fontName)), size: \(number(row.fontSize))) ?? \(system)"
    }

    private static func timing(_ motion: PlayerMotion) -> String {
        motion.style == .easeInOut ? ".easeInOut" : ".linear"
    }

    private static func ramps(_ motion: PlayerMotion?) -> String {
        guard let motion, motion.style == .custom else { return "nil" }
        return ".init(acceleration: .init(duration: \(number(motion.acceleration)), curve: .\(motion.accelerationCurve.rawValue)), deceleration: .init(duration: \(number(motion.deceleration)), curve: .\(motion.decelerationCurve.rawValue)))"
    }

    static func literal(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    result += "\\u{\(String(scalar.value, radix: 16))}"
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

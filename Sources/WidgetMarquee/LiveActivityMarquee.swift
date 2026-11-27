import CoreText
import SwiftUI
import UIKit

private final class LiveActivityMarqueeResources {}

/// A one-line marquee for a Live Activity's Lock Screen or expanded Dynamic Island.
///
/// Keep `startedAt` stable across content updates. A pass takes ten seconds by
/// default. Supply `pointsPerSecond` to keep the speed fixed across messages of
/// different lengths. The system controls the refresh rate. iOS 17 advances
/// once per second.
public struct LiveActivityMarquee: View {
    private let text: String
    private let startedAt: Date
    private let pointsPerSecond: CGFloat?
    private let timing: WidgetMarqueeTiming
    private let pauseBetweenLoops: TimeInterval
    private let sharedCycle: (travel: TimeInterval, duration: TimeInterval)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reducedLuminance

    private static let typeface = WidgetMarqueeMetrics.font
    private static let height: CGFloat = 23
    private static let gatePhases = 10

    private static let stopwatchFont = registerFont("WidgetMarqueeStopwatch")
    private static let playbackFace = registerFont("WidgetMarqueePlayback")
    private static let speedFace = registerFont("WidgetMarqueeSpeed")
    private static let gateFont = registerFont("WidgetMarqueeTimerGate")

    private static func registerFont(_ resourceName: String) -> String? {
        let postScriptName = resourceName + "-Regular"
        if UIFont(name: postScriptName, size: height) != nil { return postScriptName }

        let main = Bundle.main
        var hosts = [main, Bundle(for: LiveActivityMarqueeResources.self)]
        if main.bundleURL.pathExtension == "appex" {
            let appURL = main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let app = Bundle(url: appURL) { hosts.append(app) }
        }

        // A package may be embedded in the extension or in the containing app.
        // Missing resources should leave a readable line.
        for host in hosts {
            let packageURL = host.url(forResource: "WidgetMarquee_WidgetMarquee", withExtension: "bundle")
            let package = packageURL.flatMap(Bundle.init(url:))
            if let url = package?.url(forResource: resourceName, withExtension: "ttf")
                ?? host.url(forResource: resourceName, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                if UIFont(name: postScriptName, size: height) != nil { return postScriptName }
            }
        }
        return nil
    }

    /// Creates a marquee with the supplied message and the activity's start date.
    /// Text that fits, reduced motion and reduced luminance produce a stationary line.
    /// VoiceOver reads the original message once.
    public init(_ text: String, startedAt: Date) {
        self.init(text, startedAt: startedAt, pointsPerSecond: nil)
    }

    /// Sets the average speed during travel, its timing, and the pause after each pass.
    /// Omitting the speed gives ten seconds of travel. Nonpositive and nonfinite
    /// speeds stop the line. A nonpositive or nonfinite pause is treated as zero.
    public init(
        _ text: String, startedAt: Date, pointsPerSecond: CGFloat? = nil,
        timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0
    ) {
        self.text = text
        self.startedAt = startedAt
        self.pointsPerSecond = pointsPerSecond
        self.timing = timing
        self.pauseBetweenLoops = pauseBetweenLoops.isFinite && pauseBetweenLoops > 0 ? pauseBetweenLoops : 0
        self.sharedCycle = nil
    }

    /// Displays one row of a group. Every row starts from the group's start date
    /// and rests at the head of its message until the group starts its next pass.
    public init(_ row: WidgetMarqueeGroup.Row) {
        self.text = row.text
        self.startedAt = row.startedAt
        self.pointsPerSecond = row.pointsPerSecond
        self.timing = row.timing
        self.pauseBetweenLoops = 0
        self.sharedCycle = (row.liveTravelDuration, row.liveCycleDuration)
    }

    public var body: some View {
        GeometryReader { viewport in
            // ActivityKit limits its combined attributes and content state to 4 KB.
            // Avoid building a wide animated strip for oversized input from other callers.
            if text.utf8.count > 4_096 {
                stationary(text)
            } else {
                let line = WidgetMarqueeMetrics.line(from: text)
                let lineWidth = WidgetMarqueeMetrics.textWidth(for: line)
                let width = viewport.size.width

                if width > 0, lineWidth > width, !reduceMotion, !reducedLuminance,
                   pointsPerSecond.map({ $0.isFinite && $0 > 0 }) ?? true {
                    let unit = line + "    "
                    let period = WidgetMarqueeMetrics.liveRepeatWidth(for: line)
                    // Large messages use the two-copy clock to keep the serialized
                    // view within the WidgetKit host's archive budget.
                    if sharedCycle != nil || timing != .linear || pauseBetweenLoops > 0 || line.utf8.count > 1_024 {
                        let travel = sharedCycle?.travel ?? pointsPerSecond.map { Double(period / $0) } ?? 10
                        if travel.isFinite, travel > 0, let face = Self.playbackFace {
                            let base = CTFontCreateWithName(face as CFString, 14, nil)
                            let ruler = Font(WidgetMarqueePlayback.font(
                                base, period: period, travelDuration: travel, pause: pauseBetweenLoops,
                                timing: timing, cycleDuration: sharedCycle?.duration
                            ))
                            let strip = Self.messageStrip(unit + line)
                            clockStrip(systemClock, ruler: ruler, strip: strip, prefixPeriods: 1, period: period, width: width)
                        } else {
                            stationary(line)
                        }
                    } else if let pointsPerSecond {
                        if let face = Self.speedFace {
                            speedStrip(unit: unit, period: period, width: width, face: face, speed: pointsPerSecond)
                        } else {
                            stationary(line)
                        }
                    } else {
                        let strip = Self.messageStrip(unit + line)
                        // SwiftUICore and the stopwatch format first shipped in the iOS 18 SDK.
                        #if canImport(SwiftUICore)
                        if #available(iOS 18.0, *), let face = Self.stopwatchFont {
                            stopwatchStrip(strip, period: period, width: width, face: face)
                        } else {
                            gateOrStationary(strip, line: line, period: period, width: width)
                        }
                        #else
                        gateOrStationary(strip, line: line, period: period, width: width)
                        #endif
                    }
                } else {
                    stationary(line)
                }
            }
        }
        .frame(height: Self.height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    private static func messageStrip(_ text: String) -> Text {
        // WidgetKit can overlap glyphs when it archives a very wide text run.
        // Keep grapheme clusters intact and separate runs with a subpixel
        // baseline difference. VoiceOver uses the original message on the view.
        if text.utf8.count <= 512 { return Text(verbatim: text).font(Font(typeface)) }
        let font = Font(typeface)
        var runs: [Text] = []
        var start = text.startIndex
        while start < text.endIndex {
            let limit = text.index(start, offsetBy: 128, limitedBy: text.endIndex) ?? text.endIndex
            let end: String.Index
            if limit < text.endIndex, let space = text[start..<limit].lastIndex(where: \.isWhitespace) {
                end = text.index(after: space)
            } else {
                end = limit
            }
            let run = Text(verbatim: String(text[start..<end])).font(font)
            runs.append(run.baselineOffset(runs.count.isMultiple(of: 2) ? 0 : 1.0 / 1024))
            start = end
        }
        while runs.count > 1 {
            runs = stride(from: 0, to: runs.count, by: 2).map { index in
                index + 1 < runs.count ? Text("\(runs[index])\(runs[index + 1])") : runs[index]
            }
        }
        return runs[0]
    }

    private func stationary(_ line: String) -> some View {
        Text(verbatim: line)
            .font(Font(Self.typeface)).lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Each axis controls one digit in one clock field. Its advance is the
    /// negative distance traveled by that digit, modulo the repeated line width.
    static func speedFont(_ base: CTFont, period: CGFloat, pointsPerSecond: CGFloat) -> CTFont {
        // Adding 100 full text widths per second leaves every centisecond unchanged.
        let speed = pointsPerSecond.truncatingRemainder(dividingBy: period * 100)
        var axes: [UInt32: CGFloat] = [:]
        for (place, maximum, seconds) in WidgetMarqueePlayback.clockPlaces {
            for digit in 1...maximum {
                let cycles = speed * seconds * CGFloat(digit) / period
                let tag = ("W" + place + String(digit)).utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                axes[tag] = cycles.rounded(.up) - cycles
            }
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base), [kCTFontVariationAttribute: axes] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, period / 24, nil)
    }

    private func speedStrip(unit: String, period: CGFloat, width: CGFloat, face: String, speed: CGFloat) -> some View {
        let base = CTFontCreateWithName(face as CFString, 14, nil)
        let ruler = Font(Self.speedFont(base, period: period, pointsPerSecond: speed))
        // Each of the seven positional digits contributes less than one full
        // width. Eight copies keep the viewport filled at every combination.
        let message = Self.messageStrip(String(repeating: unit, count: 8))
        return clockStrip(systemClock, ruler: ruler, strip: message, prefixPeriods: 7, period: period, width: width)
    }

    private var systemClock: Text {
        #if canImport(SwiftUICore)
        if #available(iOS 18.0, *) {
            return Text(.currentDate, format: .stopwatch(
                startingAt: startedAt, showsHours: true, maxFieldCount: 4, maxPrecision: .milliseconds(10)
            ))
        }
        #endif
        return Text(startedAt, style: .timer)
    }

    #if canImport(SwiftUICore)
    @available(iOS 18.0, *)
    private func stopwatchStrip(_ strip: Text, period: CGFloat, width: CGFloat, face: String) -> some View {
        // The font shapes the final s.cc digits into one invisible prefix.
        // At this size its advance decreases by period/1,000 per centisecond.
        let rulerFont = Font.custom(face, fixedSize: period / 24)
        let clock = Text(.currentDate, format: .stopwatch(
            startingAt: startedAt, showsHours: false, maxFieldCount: 4, maxPrecision: .milliseconds(10)
        ))
        return clockStrip(clock, ruler: rulerFont, strip: strip, prefixPeriods: 1, period: period, width: width)
    }
    #endif

    private func clockStrip(
        _ clock: Text, ruler: Font, strip: Text, prefixPeriods: Int, period: CGFloat, width: CGFloat
    ) -> some View {
        // Keep the invisible clock to the left of right-to-left messages.
        let directionMark = Text(verbatim: "\u{200E}").font(ruler)
        return Text("\(directionMark)\(clock.font(ruler))\(strip)")
            .lineLimit(1)
            .frame(width: CGFloat(2 * prefixPeriods + 1) * period + 2, height: Self.height, alignment: .leading)
            .offset(x: -CGFloat(prefixPeriods) * period)
            .frame(width: width, height: Self.height, alignment: .leading)
            .clipped()
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
            // Native digit changes already drive motion. A second transition
            // would tween the equivalent copies backward at a minute boundary.
            .contentTransition(.identity)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }

    @ViewBuilder
    private func gateOrStationary(_ strip: Text, line: String, period: CGFloat, width: CGFloat) -> some View {
        if let face = Self.gateFont {
            gatedStrip(strip, period: period, width: width, face: face)
        } else {
            stationary(line)
        }
    }

    private func gatedStrip(_ strip: Text, period: CGFloat, width: CGFloat, face: String) -> some View {
        ZStack(alignment: .leading) {
            ForEach(0..<Self.gatePhases, id: \.self) { phase in
                strip.lineLimit(1).fixedSize()
                    .offset(x: -period * CGFloat(phase) / CGFloat(Self.gatePhases))
                    .frame(width: width, height: Self.height, alignment: .leading)
                    .clipped()
                    .mask { gate(for: phase, width: width, face: face) }
            }
        }
        .frame(width: width, height: Self.height, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func gate(for phase: Int, width: CGFloat, face: String) -> some View {
        let offset = (Self.gatePhases - phase) % Self.gatePhases
        return Text(startedAt.addingTimeInterval(-Double(offset)), style: .timer)
            .font(.custom(face, fixedSize: Self.height))
            .foregroundStyle(.white)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            .frame(width: Self.height * 12, height: Self.height, alignment: .trailing)
            .frame(width: Self.height, height: Self.height, alignment: .trailing)
            .clipped()
            .scaleEffect(x: width / Self.height, y: 1, anchor: .leading)
            .frame(width: width, height: Self.height, alignment: .leading)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
    }
}

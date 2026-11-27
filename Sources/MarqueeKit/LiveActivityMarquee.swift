import CoreText
import SwiftUI
import UIKit

private final class LiveActivityMarqueeResources {}

/// A horizontal line or upright vertical column for a Live Activity’s Lock Screen or expanded Dynamic Island.
///
/// Keep `startedAt` stable across content updates. A pass takes ten seconds by
/// default. Supply `pointsPerSecond` to keep the speed fixed across messages of
/// different lengths. The system controls the refresh rate. iOS 17 advances
/// once per second.
public struct LiveActivityMarquee: View {
    private let text: String
    private let axis: MarqueeAxis
    private let startedAt: Date
    private let pointsPerSecond: CGFloat?
    private let ramps: MarqueeRamps?
    private let repeatSpacing: CGFloat?
    private let timing: WidgetMarqueeTiming
    private let pauseBetweenLoops: TimeInterval
    private let sharedCycle: (travel: TimeInterval, duration: TimeInterval, motion: WidgetMarqueeGroup.Motion?)?

    @Environment(\.marqueeEdgeFade) private var edgeFade
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reducedLuminance

    private let horizontalFont: UIFont?
    private var typeface: UIFont { horizontalFont ?? WidgetMarqueeMetrics.font }
    private var height: CGFloat { axis == .horizontal ? max(23, ceil(typeface.lineHeight)) : 23 }
    private static let gatePhases = 10
    private static let shortLineBytes = 1_024

    private static let stopwatchFont = registerFont("WidgetMarqueeStopwatch")
    private static let playbackFace = registerFont("WidgetMarqueePlayback", extension: "woff2", face: "WidgetMarqueePlaybackDirect-Regular")
    private static let speedFace = registerFont("WidgetMarqueeSpeed")
    private static let spacingFont = registerFont("MarqueeRepeatSpace")
    private static let gateFont = registerFont("WidgetMarqueeTimerGate")

    private static func registerFont(_ resourceName: String, extension fileExtension: String = "ttf", face: String? = nil) -> String? {
        let postScriptName = face ?? resourceName + "-Regular"
        if UIFont(name: postScriptName, size: 14) != nil { return postScriptName }

        let main = Bundle.main
        var hosts = [main, Bundle(for: LiveActivityMarqueeResources.self)]
        if main.bundleURL.pathExtension == "appex" {
            let appURL = main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let app = Bundle(url: appURL) { hosts.append(app) }
        }

        // A package may be embedded in the extension or in the containing app.
        // Missing resources should leave a readable line.
        for host in hosts {
            let packageURL = host.url(forResource: "MarqueeKit_MarqueeKit", withExtension: "bundle")
            let package = packageURL.flatMap(Bundle.init(url:))
            if let url = package?.url(forResource: resourceName, withExtension: fileExtension)
                ?? host.url(forResource: resourceName, withExtension: fileExtension) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                if UIFont(name: postScriptName, size: 14) != nil { return postScriptName }
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
    /// A vertical marquee shows one upright grapheme per cell and scrolls upward. Give its viewport a height
    /// with `.frame(height:)`. Omitting the speed gives ten seconds of travel. Nonpositive
    /// or nonfinite speeds stop the marquee. Nonpositive or nonfinite pauses become zero.
    /// Set `repeatSpacing` to the distance in points between consecutive copies.
    /// With custom `ramps`, `pointsPerSecond` specifies the cruising speed.
    /// Supply a UIKit font to measure and draw horizontal text at the same size and weight.
    public init(
        _ text: String, startedAt: Date, pointsPerSecond: CGFloat? = nil,
        timing: WidgetMarqueeTiming = .linear, pauseBetweenLoops: TimeInterval = 0,
        axis: MarqueeAxis = .horizontal, horizontalFont: UIFont? = nil, repeatSpacing: CGFloat? = nil,
        ramps: MarqueeRamps? = nil
    ) {
        self.text = text
        self.ramps = ramps
        self.repeatSpacing = WidgetMarqueeMetrics.normalizedRepeatSpacing(repeatSpacing)
        self.axis = axis
        self.horizontalFont = horizontalFont
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
        self.ramps = row.ramps
        self.repeatSpacing = row.repeatSpacing
        self.axis = row.axis
        self.horizontalFont = row.horizontalFont
        self.startedAt = row.startedAt
        self.pointsPerSecond = row.pointsPerSecond
        self.timing = row.timing
        self.pauseBetweenLoops = 0
        self.sharedCycle = (row.liveTravelDuration, row.liveCycleDuration, row.liveMotion)
    }

    public var body: some View {
        GeometryReader { viewport in
            let length = axis == .vertical ? viewport.size.height : viewport.size.width
            if text.utf8.count > 4_096 {
                stationary(text, length: length)
            } else {
                let line = WidgetMarqueeMetrics.line(from: text)
                let contentLength = WidgetMarqueeMetrics.contentLength(for: line, axis: axis, horizontalFont: horizontalFont)
                if length > 0, contentLength > length {
                    let edges = edgeFade.resolved(in: length)
                    Group {
                        if !reduceMotion, !reducedLuminance,
                           redactionReasons.intersection([.placeholder, .privacy]).isEmpty,
                           (axis == .horizontal || repeatSpacing == nil || Self.spacingFont != nil),
                           (repeatSpacing ?? 0) < CGFloat.greatestFiniteMagnitude / 32,
                           pointsPerSecond.map({ $0.isFinite && $0 > 0 }) ?? true {
                            moving(line, contentLength: contentLength, length: length, inset: edges.headInset)
                                .transition(.identity)
                        } else {
                            stationary(line, length: length, inset: edges.headInset)
                                .transition(.identity)
                        }
                    }
                    .modifier(MarqueeEdgeMask(axis: axis, edges: edges))
                } else {
                    stationary(line, length: length)
                }
            }
        }
        .frame(width: axis == .vertical ? WidgetMarqueeMetrics.columnWidth : nil,
               height: axis == .horizontal ? height : nil)
        .clipped()
        // WidgetKit otherwise cross-fades the old and new text positions
        // when the host replaces a stationary or redacted presentation.
        .contentTransition(.identity)
        .transition(.identity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    @ViewBuilder
    private func moving(_ line: String, contentLength: CGFloat, length: CGFloat, inset: CGFloat) -> some View {
        let scheduledPeriod = axis == .vertical
            ? contentLength + (repeatSpacing ?? WidgetMarqueeMetrics.gap)
            : WidgetMarqueeMetrics.liveRepeatWidth(for: line, font: horizontalFont, repeatSpacing: repeatSpacing)
        let usesPlayback = axis == .vertical || sharedCycle != nil || repeatSpacing != nil || ramps != nil
            || timing != .linear || pauseBetweenLoops > 0 || line.utf8.count > Self.shortLineBytes
        let measuresStrip = axis == .horizontal && (usesPlayback || pointsPerSecond == nil)
        let period = measuresStrip ? renderedRepeatWidth(for: line, fallback: scheduledPeriod) : scheduledPeriod
        // An inset wider than the loop gap exposes the end of the preceding copy.
        let gap = repeatSpacing ?? (scheduledPeriod - contentLength)
        let previous = inset > gap ? 1 : 0
        if usesPlayback {
            let baseTravel = pointsPerSecond.map { Double(scheduledPeriod / $0) } ?? 10
            let motion = sharedCycle?.motion ?? ramps.flatMap {
                WidgetMarqueeGroup.Motion.custom($0, baseTravel: baseTravel, fixedDuration: pointsPerSecond == nil)
            }
            let travel = sharedCycle?.travel ?? motion?.duration ?? baseTravel
            if travel.isFinite, travel > 0, let face = Self.playbackFace {
                let base = CTFontCreateWithName(face as CFString, 14, nil)
                let ruler = Font(WidgetMarqueePlayback.font(
                    base, period: period, travelDuration: travel, pause: pauseBetweenLoops,
                    timing: timing, cycleDuration: sharedCycle?.duration, groupMotion: motion
                ))
                if axis == .vertical {
                    if let tile = LiveActivityVerticalStrip.unit(for: line, repeatSpacing: repeatSpacing) {
                        let strip = Self.joined(Array(repeating: tile, count: 2 + previous))
                        clockStrip(clock(startingAt: startedAt), ruler: ruler, strip: strip, prefixPeriods: 1 + previous,
                                   period: period, width: length, inset: inset)
                            .frame(width: length, height: height)
                            .rotationEffect(.degrees(90))
                            .frame(width: WidgetMarqueeMetrics.columnWidth, height: length)
                    } else {
                        stationary(line, length: length, inset: inset)
                    }
                } else {
                    horizontalStrip(line, clock: clock(startingAt: startedAt), units: 1 + previous, ruler: ruler, prefixPeriods: 1 + previous,
                                    period: period, width: length, inset: inset)
                }
            } else {
                stationary(line, length: length, inset: inset)
            }
        } else if let pointsPerSecond {
            if let face = Self.speedFace {
                let base = CTFontCreateWithName(face as CFString, 14, nil)
                let ruler = Font(Self.speedFont(base, period: period, pointsPerSecond: pointsPerSecond))
                // Seven clock digits each contribute less than one period.
                horizontalStrip(line, clock: clock(startingAt: startedAt), units: 8 + previous, endsWithGap: true,
                                ruler: ruler, prefixPeriods: 7 + previous, period: period, width: length, inset: inset)
            } else {
                stationary(line, length: length, inset: inset)
            }
        } else {
            #if canImport(SwiftUICore)
            if #available(iOS 18.0, *), let face = Self.stopwatchFont {
                // This face shapes the final s.cc digits into one invisible prefix.
                horizontalStrip(line, clock: clock(startingAt: startedAt, showsHours: false), units: 1 + previous,
                                ruler: .custom(face, fixedSize: period / 24), prefixPeriods: 1 + previous,
                                period: period, width: length, inset: inset)
            } else {
                gateOrStationary(repeatedLine(line, units: 1 + previous), line: line, period: period, width: length, previous: previous, inset: inset)
            }
            #else
            gateOrStationary(repeatedLine(line, units: 1 + previous), line: line, period: period, width: length, previous: previous, inset: inset)
            #endif
        }
    }

    // An inkless one-em glyph gives the clock and the visible copies the same
    // fractional spacing, independent of the message font or bitmap size.
    static func spacer(_ length: CGFloat) -> Text {
        let glyph = length > 0 ? "\u{E000}" : "\u{200B}"
        return Text(verbatim: glyph).font(.custom(spacingFont ?? "MarqueeRepeatSpace-Regular",
                                                   fixedSize: length > 0 ? length : 1))
    }

    private func repeatedLine(_ line: String, units: Int, endsWithGap: Bool = false) -> Text {
        let repeated = String(repeating: line + "    ", count: units)
        return messageStrip(endsWithGap ? repeated : repeated + line)
    }

    private func messageStrip(_ text: String) -> Text {
        if text.utf8.count <= 512 { return Text(verbatim: text).font(Font(typeface)) }
        return Text(attributedMessage(text)).font(Font(typeface))
    }

    private func attributedMessage(_ text: String) -> AttributedString {
        guard text.utf8.count > 512 else { return AttributedString(text) }
        // WidgetKit can overlap glyphs in wide runs. Alternate a subpixel baseline
        // offset to keep runs separate without splitting grapheme clusters.
        var message = AttributedString()
        var alternate = false
        var start = text.startIndex
        while start < text.endIndex {
            let limit = text.index(start, offsetBy: 128, limitedBy: text.endIndex) ?? text.endIndex
            let end: String.Index
            if limit < text.endIndex, let space = text[start..<limit].lastIndex(where: \.isWhitespace) {
                end = text.index(after: space)
            } else {
                end = limit
            }
            var run = AttributedString(String(text[start..<end]))
            run.baselineOffset = alternate ? 1.0 / 1024 : 0
            message.append(run)
            alternate.toggle()
            start = end
        }
        return message
    }

    static func joined(_ segments: [Text]) -> Text {
        var runs = segments
        while runs.count > 1 {
            runs = stride(from: 0, to: runs.count, by: 2).map { index in
                index + 1 < runs.count ? Text("\(runs[index])\(runs[index + 1])") : runs[index]
            }
        }
        return runs.first ?? Text(verbatim: "")
    }

    @ViewBuilder
    private func stationary(_ line: String, length: CGFloat, inset: CGFloat = 0) -> some View {
        Group {
            if axis == .vertical {
                LiveActivityVerticalStrip.stationary(line, viewport: length)
            } else {
                Text(verbatim: line)
                    .font(Font(typeface)).lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .offset(x: axis == .horizontal ? inset : 0, y: axis == .vertical ? inset : 0)
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

    private func clock(startingAt date: Date, showsHours: Bool = true) -> Text {
        #if canImport(SwiftUICore)
        if #available(iOS 18.0, *) {
            return Text(.currentDate, format: .stopwatch(
                startingAt: date, showsHours: showsHours, maxFieldCount: 4, maxPrecision: .milliseconds(10)
            ))
        }
        #endif
        return Text(date, style: .timer)
    }

    func horizontalStrip(
        _ line: String, clock: Text, units: Int, endsWithGap: Bool = false, ruler: Font, prefixPeriods: Int,
        period: CGFloat, width: CGFloat, inset: CGFloat
    ) -> some View {
        // Advance the entire strip at one timestamp. Blending different positions
        // gives moving glyphs a second edge, even when the two clocks are close.
        clockStrip(clock, ruler: ruler, strip: horizontalContent(line, units: units, endsWithGap: endsWithGap),
                   prefixPeriods: prefixPeriods, period: period, width: width, inset: inset)
    }

    func horizontalContent(_ line: String, units: Int, endsWithGap: Bool = false) -> Text {
        guard let spacing = repeatSpacing else { return repeatedLine(line, units: units, endsWithGap: endsWithGap) }
        // Keep both copies and their gap in the message font. A separate spacer font
        // can change the shaped distance between heads in WidgetKit's archived Text.
        let spaces = "    "
        var gap = AttributedString(spaces)
        let naturalWidth = (spaces as NSString).size(withAttributes: [.font: typeface]).width
        gap.kern = (spacing - naturalWidth) / CGFloat(spaces.count)
        let message = attributedMessage(line)
        var strip = AttributedString()
        for _ in 0..<units {
            strip.append(message)
            strip.append(gap)
        }
        if !endsWithGap { strip.append(message) }
        return Text(strip).font(Font(typeface))
    }

    func renderedRepeatWidth(for line: String, fallback: CGFloat) -> CGFloat {
        func width(of text: Text) -> CGFloat {
            let renderer = ImageRenderer(content: text.fixedSize().environment(\.layoutDirection, .leftToRight))
            var width: CGFloat = 0
            renderer.render { size, _ in width = size.width }
            return width
        }
        // Measuring the gap between two heads retains the spacing that a trailing
        // space alone can lose. Only ask SwiftUI for the size, without drawing pixels.
        let pitch = width(of: horizontalContent(line, units: 1)) - width(of: messageStrip(line))
        return pitch.isFinite && pitch > 0 ? pitch : fallback
    }

    private func clockStrip(
        _ clock: Text, ruler: Font, strip: Text, prefixPeriods: Int, period: CGFloat, width: CGFloat, inset: CGFloat
    ) -> some View {
        // Keep the invisible clock to the left of right-to-left messages.
        let directionMark = Text(verbatim: "\u{200E}").font(ruler)
        return Text("\(directionMark)\(clock.font(ruler))\(strip)")
            .lineLimit(1)
            .frame(width: CGFloat(2 * max(1, prefixPeriods) + 1) * period + 2, height: height, alignment: .leading)
            .offset(x: -CGFloat(prefixPeriods) * period + inset)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
            // Native digit changes already drive motion. A second transition
            // would tween the equivalent copies backward at a minute boundary.
            .contentTransition(.identity)
    }

    @ViewBuilder
    private func gateOrStationary(_ strip: Text, line: String, period: CGFloat, width: CGFloat, previous: Int, inset: CGFloat) -> some View {
        if let face = Self.gateFont {
            gatedStrip(strip, period: period, width: width, face: face, previous: previous, inset: inset)
        } else {
            stationary(line, length: width, inset: inset)
        }
    }

    private func gatedStrip(_ strip: Text, period: CGFloat, width: CGFloat, face: String, previous: Int, inset: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(0..<Self.gatePhases, id: \.self) { phase in
                strip.lineLimit(1).fixedSize()
                    .offset(x: inset - period * (CGFloat(previous) + CGFloat(phase) / CGFloat(Self.gatePhases)))
                    .frame(width: width, height: height, alignment: .leading)
                    .clipped()
                    .mask { gate(for: phase, width: width, face: face) }
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func gate(for phase: Int, width: CGFloat, face: String) -> some View {
        let offset = (Self.gatePhases - phase) % Self.gatePhases
        return Text(startedAt.addingTimeInterval(-Double(offset)), style: .timer)
            .font(.custom(face, fixedSize: height))
            .foregroundStyle(.white)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            .frame(width: height * 12, height: height, alignment: .trailing)
            .frame(width: height, height: height, alignment: .trailing)
            .clipped()
            .scaleEffect(x: width / height, y: 1, anchor: .leading)
            .frame(width: width, height: height, alignment: .leading)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
    }
}

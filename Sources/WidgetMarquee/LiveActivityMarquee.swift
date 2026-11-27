import CoreText
import SwiftUI
import UIKit

private final class LiveActivityMarqueeResources {}

/// A one-line marquee for a Live Activity's Lock Screen or expanded Dynamic Island.
///
/// Keep `startedAt` stable across content updates. On iOS 18 and later the
/// system's stopwatch text drives a ten-second pass. iOS 17 uses ten positions
/// per pass. The system controls the refresh rate of both presentations.
public struct LiveActivityMarquee: View {
    private let text: String
    private let startedAt: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reducedLuminance

    private static let typeface = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let height: CGFloat = 23
    private static let gatePhases = 10

    private static let stopwatchFont = registerFont("WidgetMarqueeStopwatch")
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
        self.text = text
        self.startedAt = startedAt
    }

    public var body: some View {
        GeometryReader { viewport in
            // ActivityKit limits its combined attributes and content state to 4 KB.
            // Avoid building a wide animated strip for oversized input from other callers.
            if text.utf8.count > 4_096 {
                stationary(text)
            } else {
                let line = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
                let attributes = [NSAttributedString.Key.font: Self.typeface]
                let lineWidth = ceil((line as NSString).size(withAttributes: attributes).width)
                let width = viewport.size.width

                if width > 0, lineWidth > width, !reduceMotion, !reducedLuminance {
                    let unit = line + "    "
                    let period = (unit as NSString).size(withAttributes: attributes).width
                    let strip = Text(verbatim: unit + line).font(Font(Self.typeface))
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

    private func stationary(_ line: String) -> some View {
        Text(verbatim: line)
            .font(Font(Self.typeface)).lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    #if canImport(SwiftUICore)
    @available(iOS 18.0, *)
    private func stopwatchStrip(_ strip: Text, period: CGFloat, width: CGFloat, face: String) -> some View {
        // The font shapes the final s.cc digits into one invisible prefix.
        // At this size its advance decreases by period/1,000 per centisecond.
        let rulerFont = Font.custom(face, fixedSize: period / 24)
        let clock = Text(.currentDate, format: .stopwatch(
            startingAt: startedAt, showsHours: false, maxFieldCount: 4, maxPrecision: .milliseconds(10)
        )).font(rulerFont)
        // Keep the invisible clock to the left of right-to-left messages.
        let directionMark = Text(verbatim: "\u{200E}").font(rulerFont)
        return Text("\(directionMark)\(clock)\(strip)")
            .lineLimit(1)
            .frame(width: 3 * period + 2, height: Self.height, alignment: .leading)
            .offset(x: -period)
            .frame(width: width, height: Self.height, alignment: .leading)
            .clipped()
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
    }
    #endif

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

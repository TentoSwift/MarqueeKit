import CoreText
import Foundation

enum WidgetMarqueePlayback {
    // These are the positional-digit features in the bundled playback font.
    static let clockPlaces: [(String, Int, Double)] = [
        ("HR", 9, 3600), ("MT", 5, 600), ("MU", 9, 60), ("ST", 5, 10),
        ("SU", 9, 1), ("DT", 9, 0.1), ("DC", 9, 0.01)
    ]
    private static let phaseCount = 4096

    static func font(_ base: CTFont, period: CGFloat, travelDuration: TimeInterval,
                     pause: TimeInterval, timing: WidgetMarqueeTiming, cycleDuration: TimeInterval? = nil) -> CTFont {
        // Grouped rows use the very same cycle when quantizing the clock digits.
        let cycle = cycleDuration ?? (travelDuration + pause)
        let movingFraction = cycle.isFinite
            ? travelDuration / cycle
            : (travelDuration / 2) / (travelDuration / 2 + pause / 2)
        // A clock digit selects its contribution to the phase. The font adds
        // those contributions modulo one cycle, including when a digit carries.
        var features: [[CFString: Any]] = []
        for (place, maximum, seconds) in clockPlaces {
            for digit in 1...maximum {
                let offset = (seconds * Double(digit)).truncatingRemainder(dividingBy: cycle)
                let phase = Int((offset / cycle * Double(phaseCount)).rounded()) % phaseCount
                features.append([
                    kCTFontOpenTypeFeatureTag: "W" + place + String(digit),
                    kCTFontOpenTypeFeatureValue: phase + 1
                ])
            }
        }
        features.append([kCTFontOpenTypeFeatureTag: "EASE",
                         kCTFontOpenTypeFeatureValue: timing == .easeInOut ? 1 : 0])
        // DUTY maps the moving portion to a full pass and the rest to the head.
        let dutyAxis: UInt32 = 0x44555459
        let attributes: [CFString: Any] = [
            kCTFontFeatureSettingsAttribute: features,
            kCTFontVariationAttribute: [dutyAxis: movingFraction]
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                                  attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, period / 24, nil)
    }
}

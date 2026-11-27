import CoreText
import Foundation

enum WidgetMarqueePlayback {
    // These are the positional-digit features in the bundled playback font.
    static let clockPlaces: [(String, Int, Double)] = [
        ("HR", 9, 3600), ("MT", 5, 600), ("MU", 9, 60), ("ST", 5, 10),
        ("SU", 9, 1), ("DT", 9, 0.1), ("DC", 9, 0.01)
    ]
    private static let phaseCount = 4096
    // Matches the phase samples in make_playback_font.py. Closely spaced samples
    // near zero also resolve short travel followed by a much longer group pause.
    private static let groupSamples: [(axis: UInt32, phase: Double)] = {
        var phases = Array(0..<16)
        for (end, step) in [(32, 2), (64, 4), (128, 8), (256, 16), (phaseCount + 1, 32)] {
            phases.append(contentsOf: stride(from: 8 * step, to: end, by: step))
        }
        return phases.enumerated().map { index, phase in
            let axis = String(format: "P%03d", index).utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return (axis, Double(phase) / Double(phaseCount))
        }
    }()

    static func font(_ base: CTFont, period: CGFloat, travelDuration: TimeInterval,
                     pause: TimeInterval, timing: WidgetMarqueeTiming, cycleDuration: TimeInterval? = nil,
                     groupMotion: WidgetMarqueeGroup.Motion? = nil) -> CTFont {
        // Grouped rows use the very same cycle when quantizing the clock digits.
        let cycle = cycleDuration ?? (travelDuration + pause)
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
        let axes: [UInt32: Double]
        if let groupMotion {
            features.append([kCTFontOpenTypeFeatureTag: "GRUP", kCTFontOpenTypeFeatureValue: 1])
            // Sample on the actual clock grid. Moving a sample to a sibling's
            // finishing time would change this row's speed during its cruise.
            axes = Dictionary(uniqueKeysWithValues: groupSamples.compactMap { sample in
                let remaining = 1 - groupMotion.progress(at: sample.phase * cycle)
                return remaining > 0 ? (sample.axis, remaining) : nil
            })
        } else {
            features.append([kCTFontOpenTypeFeatureTag: "EASE",
                             kCTFontOpenTypeFeatureValue: timing == .easeInOut ? 1 : 0])
            // DUTY maps the moving portion to a full pass and the rest to the head.
            let movingFraction = cycle.isFinite
                ? travelDuration / cycle
                : (travelDuration / 2) / (travelDuration / 2 + pause / 2)
            axes = [0x44555459: movingFraction]
        }
        let attributes: [CFString: Any] = [
            kCTFontFeatureSettingsAttribute: features,
            kCTFontVariationAttribute: axes
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                                  attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, period / 24, nil)
    }
}

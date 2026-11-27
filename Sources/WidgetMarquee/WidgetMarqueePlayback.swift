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
    private static let groupSamples: [(axis: UInt32, tick: Int)] = {
        var phases = Array(0..<32)
        for (end, step) in [(64, 4), (128, 8), (256, 16), (phaseCount + 1, 32)] {
            phases.append(contentsOf: stride(from: 8 * step, to: end, by: step))
        }
        return phases.enumerated().map { index, phase in
            let axis = String(format: "P%03d", index).utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return (axis, phase)
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
                for (bit, bank) in ["A", "B", "C"].enumerated() {
                    let nibble = (phase >> (bit * 4)) & 15
                    if nibble > 0 {
                        features.append([
                            kCTFontOpenTypeFeatureTag: bank + place + String(digit),
                            kCTFontOpenTypeFeatureValue: nibble
                        ])
                    }
                }
            }
        }
        // The font interpolates these distances on the actual clock grid.
        // Keep the arithmetic in fractions, including for exceptionally long pauses.
        let movingFraction = cycle.isFinite
            ? travelDuration / cycle
            : (travelDuration / 2) / (travelDuration / 2 + pause / 2)
        // Align a standalone stop to a knot so a linear pass never leaks
        // into the hold. The first 32 ticks are all knots, preserving the
        // native-clock precision of the restart after rotating the phase.
        let stop = min(phaseCount, max(1, Int((movingFraction * Double(phaseCount)).rounded())))
        let shift = groupMotion == nil
            ? ((groupSamples.first { $0.tick >= stop }?.tick ?? stop) - stop)
            : 0
        for bit in 0..<5 where shift & (1 << bit) != 0 {
            features.append([kCTFontOpenTypeFeatureTag: "SHF" + String(bit), kCTFontOpenTypeFeatureValue: 1])
        }
        let axes = Dictionary(uniqueKeysWithValues: groupSamples.compactMap { sample -> (UInt32, Double)? in
            let relative = sample.tick - shift
            let tick = relative < 0 ? relative + phaseCount : relative
            let phase = Double(tick) / Double(phaseCount)
            let progress: Double
            if let groupMotion {
                progress = groupMotion.progress(at: phase * cycle)
            } else if tick == 0 {
                progress = 0
            } else if tick >= stop {
                progress = 1
            } else {
                progress = timing.progress(min(1, phase / movingFraction))
            }
            return progress < 1 ? (sample.axis, 1 - progress) : nil
        })
        let attributes: [CFString: Any] = [
            kCTFontFeatureSettingsAttribute: features,
            kCTFontVariationAttribute: axes
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
                                                                  attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, period / 24, nil)
    }
}

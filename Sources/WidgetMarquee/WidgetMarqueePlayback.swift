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

    /// Interpolating past a shorter row's stop would give each row a different
    /// slope in that interval. Put each shared stop on a font sample instead.
    private static func groupSampleTimes(arrivals: [TimeInterval], cycle: TimeInterval) -> [TimeInterval] {
        var times = groupSamples.map { $0.phase * cycle }
        let end = times.count - 1
        var arrivalIndex = 0
        var lastAnchor = 0
        // Only intermediate arrivals separate rows that are moving together.
        for upper in 1...end {
            let first = arrivalIndex
            while arrivalIndex < arrivals.count - 1, arrivals[arrivalIndex] <= times[upper] {
                arrivalIndex += 1
            }
            guard first < arrivalIndex else { continue }
            let lower = upper - 1
            if upper == end {
                // The cycle endpoints always keep their exact start/end values.
                if lower > lastAnchor { times[lower] = arrivals[first] }
            } else if arrivalIndex - first > 1, lower > lastAnchor {
                // If a cell contains several stops, use both available ends.
                // Additional stops within that cell share its interpolation.
                times[lower] = arrivals[first]
                times[upper] = arrivals[arrivalIndex - 1]
                lastAnchor = upper
            } else {
                times[upper] = arrivals[first]
                lastAnchor = upper
            }
        }
        return times
    }

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
            let times = groupSampleTimes(arrivals: groupMotion.groupArrivals, cycle: cycle)
            axes = Dictionary(uniqueKeysWithValues: zip(groupSamples, times).compactMap { sample, time in
                let remaining = 1 - groupMotion.progress(at: time)
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

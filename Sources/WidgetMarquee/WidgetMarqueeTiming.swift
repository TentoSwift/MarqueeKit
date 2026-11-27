/// Controls how the marquee moves during one pass. Any pause follows the pass.
public enum WidgetMarqueeTiming: String, Codable, Sendable {
    /// Moves at a constant speed.
    case linear
    /// Starts and ends at rest, reaching its highest speed halfway through the pass.
    case easeInOut

    func progress(_ fraction: Double) -> Double {
        switch self {
        case .linear: return fraction
        case .easeInOut: return fraction * fraction * (3 - 2 * fraction)
        }
    }
}

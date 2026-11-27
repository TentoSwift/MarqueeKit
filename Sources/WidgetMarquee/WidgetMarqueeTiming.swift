/// Controls how the marquee moves during one pass. Any pause follows the pass.
public enum WidgetMarqueeTiming: String, Codable, Sendable {
    /// Moves at a constant speed.
    case linear
    /// Starts and ends at rest. In a group, each row slows for its own arrival.
    case easeInOut

    func progress(_ fraction: Double) -> Double {
        switch self {
        case .linear: return fraction
        case .easeInOut: return fraction * fraction * (3 - 2 * fraction)
        }
    }

    func speedFactor(_ fraction: Double) -> Double {
        switch self {
        case .linear: return 1
        case .easeInOut: return 6 * fraction * (1 - fraction)
        }
    }
}

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

/// Independent speed changes at the beginning and end of a pass. Custom ramps
/// take precedence over `WidgetMarqueeTiming`. When a speed is supplied it is
/// the cruising speed in points per second. The pass includes time to ramp up
/// and slow down. Without a speed, the schedule keeps its original pass duration.
public struct MarqueeRamps: Codable, Hashable, Sendable {
    /// Fraction of cruise speed as a function of ramp time. Acceleration
    /// evaluates the curve from zero to one, braking from one back to zero.
    public enum Curve: String, Codable, Sendable {
        case linear
        case easeIn
        case easeOut

        func speed(at u: Double) -> Double {
            switch self {
            case .linear: return u
            case .easeIn: return u * u
            case .easeOut: return u * (2 - u)
            }
        }

        // Integral of speed from 0 to u, divided by u.
        func averageSpeed(through u: Double) -> Double {
            switch self {
            case .linear: return u / 2
            case .easeIn: return u * u / 3
            case .easeOut: return u * (1 - u / 3)
            }
        }
    }

    public struct Ramp: Codable, Hashable, Sendable {
        /// Requested duration in seconds. Negative and nonfinite values become zero.
        public let duration: Double
        public let curve: Curve

        public init(duration: Double, curve: Curve = .linear) {
            self.duration = duration.isFinite ? max(0, duration) : 0
            self.curve = curve
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(duration: try values.decode(Double.self, forKey: .duration),
                      curve: try values.decode(Curve.self, forKey: .curve))
        }
    }

    public let acceleration: Ramp
    public let deceleration: Ramp

    /// A zero-duration end switches speed immediately. When the two ramps
    /// exceed the available distance or fixed duration, they shorten in proportion.
    public init(acceleration: Ramp = .init(duration: 0), deceleration: Ramp = .init(duration: 0)) {
        self.acceleration = acceleration
        self.deceleration = deceleration
    }
}

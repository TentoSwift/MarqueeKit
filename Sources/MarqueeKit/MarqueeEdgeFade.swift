import SwiftUI

/// The direction of travel. Vertical marquees keep each character upright.
public enum MarqueeAxis: String, Codable, Hashable, Sendable {
    case horizontal
    case vertical
}

extension View {
    /// Fades overflowing marquees to transparent at both ends of the scrolling axis.
    ///
    /// Both values are in points. At the head of a pass, the first character sits
    /// `clearance` points beyond the fully opaque end of the fade. Text that fits
    /// needs no fade. Set `length` to zero to disable the effect.
    public func marqueeEdgeFade(length: CGFloat, clearance: CGFloat = 0) -> some View {
        environment(\.marqueeEdgeFade, MarqueeEdgeFade(length: length, clearance: clearance))
    }
}

struct MarqueeEdgeFade: Equatable {
    var length: CGFloat = 0
    var clearance: CGFloat = 0

    struct Edges: Equatable {
        var length: CGFloat = 0
        var headInset: CGFloat = 0
        var fraction: CGFloat = 0
    }

    func resolved(in viewportLength: CGFloat) -> Edges {
        guard viewportLength.isFinite, viewportLength > 0, length.isFinite, length > 0 else {
            return Edges()
        }
        // Leave room for a fully opaque character even in a narrow presentation.
        let budget = max(0, (viewportLength - 20) / 2)
        let fade = min(length, budget)
        let space = clearance.isFinite ? max(0, clearance) : 0
        return Edges(length: fade, headInset: fade + min(space, budget - fade),
                     fraction: fade / viewportLength)
    }
}

private enum MarqueeEdgeFadeKey: EnvironmentKey {
    static let defaultValue = MarqueeEdgeFade()
}

extension EnvironmentValues {
    var marqueeEdgeFade: MarqueeEdgeFade {
        get { self[MarqueeEdgeFadeKey.self] }
        set { self[MarqueeEdgeFadeKey.self] = newValue }
    }
}

struct MarqueeEdgeMask: ViewModifier {
    let axis: MarqueeAxis
    let edges: MarqueeEdgeFade.Edges

    @ViewBuilder
    func body(content: Content) -> some View {
        if edges.length > 0 {
            content.mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: edges.fraction),
                    .init(color: .white, location: 1 - edges.fraction),
                    .init(color: .clear, location: 1)
                ], startPoint: axis == .horizontal ? .leading : .top,
                   endPoint: axis == .horizontal ? .trailing : .bottom)
            }
        } else {
            content
        }
    }
}

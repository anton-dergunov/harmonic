import SwiftUI

// Horizontal shake driven by an incrementing counter. Pass `animatableData`
// equal to a published Int counter; each increment plays one shake cycle.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 5
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = animatableData - animatableData.rounded(.down)
        let offset = amount * sin(t * .pi * 2 * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

import SwiftUI

public enum MediaAccessibility: Sendable, Equatable {
    case decorative
    case meaningful(String)
}

public extension View {
    @ViewBuilder
    func mediaAccessibility(_ mode: MediaAccessibility) -> some View {
        switch mode {
        case .decorative:
            accessibilityHidden(true)
        case .meaningful(let label):
            accessibilityLabel(label)
        }
    }
}

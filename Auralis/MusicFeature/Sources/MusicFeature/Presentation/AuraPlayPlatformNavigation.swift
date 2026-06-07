import SwiftUI

extension View {
    @ViewBuilder
    func auraPlayInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

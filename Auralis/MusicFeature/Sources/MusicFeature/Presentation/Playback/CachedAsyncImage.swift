import AuraUI
import SwiftUI

struct CachedAsyncImage: View {
    let url: URL
    let accessibilityLabel: String

    init(url: URL, accessibilityLabel: String) {
        self.url = url
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
                    .overlay {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    }
                    .accessibilityLabel(String(localized: "Loading artwork"))
            case .success(let image):
                image
                    .resizable()
                    .accessibilityLabel(accessibilityLabel)
            case .failure:
                placeholder
                    .overlay {
                        SystemImage("photo")
                            .font(.largeTitle)
                            .foregroundStyle(Color.textSecondary.opacity(0.3))
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(String(localized: "Artwork unavailable"))
            @unknown default:
                placeholder
                    .accessibilityLabel(String(localized: "Artwork unavailable"))
            }
        }
    }

    private var placeholder: some View {
        Color.surface
            .aspectRatio(1, contentMode: .fit)
    }
}

import AuraUI
import SwiftUI

struct CachedAsyncImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
                    .overlay {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    }
                    .accessibilityLabel("Loading artwork")
            case .success(let image):
                image
                    .resizable()
                    .accessibilityLabel("Artwork")
            case .failure:
                placeholder
                    .overlay {
                        SystemImage("photo")
                            .font(.largeTitle)
                            .foregroundStyle(Color.textSecondary.opacity(0.3))
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Artwork unavailable")
            @unknown default:
                placeholder
                    .accessibilityLabel("Artwork unavailable")
            }
        }
    }

    private var placeholder: some View {
        Color.surface
            .aspectRatio(1, contentMode: .fit)
    }
}

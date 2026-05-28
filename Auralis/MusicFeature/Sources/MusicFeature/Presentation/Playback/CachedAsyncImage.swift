import AuraUI
import SwiftUI

struct CachedAsyncImage: View {
    let url: URL
    let mediaAccessibility: MediaAccessibility

    init(url: URL, accessibilityLabel: String) {
        self.url = url
        mediaAccessibility = .meaningful(accessibilityLabel)
    }

    init(url: URL, mediaAccessibility: MediaAccessibility) {
        self.url = url
        self.mediaAccessibility = mediaAccessibility
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                phaseView(label: String(localized: "Loading artwork")) {
                    placeholder
                        .overlay {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                        }
                }
            case .success(let image):
                image
                    .resizable()
                    .mediaAccessibility(mediaAccessibility)
            case .failure:
                phaseView(label: String(localized: "Artwork unavailable")) {
                    placeholder
                        .overlay {
                            SystemImage("photo")
                                .font(.largeTitle)
                                .foregroundStyle(Color.textSecondary.opacity(0.3))
                                .accessibilityHidden(true)
                        }
                }
            @unknown default:
                phaseView(label: String(localized: "Artwork unavailable")) {
                    placeholder
                }
            }
        }
    }

    private var placeholder: some View {
        Color.surface
            .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func phaseView<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        switch mediaAccessibility {
        case .decorative:
            content()
                .mediaAccessibility(.decorative)
        case .meaningful:
            content()
                .mediaAccessibility(.meaningful(label))
        }
    }
}

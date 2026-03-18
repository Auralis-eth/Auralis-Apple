import SwiftUI

struct AuraSectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SubheadlineFontText(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailing
            }

            if let subtitle, !subtitle.isEmpty {
                SecondaryText(subtitle)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension AuraSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AuraSurfaceCard {
            AuraSectionHeader(title: "Energy")
        }

        AuraSurfaceCard {
            AuraSectionHeader(title: "Ethereum Gas Tracker", subtitle: "Last updated 9:41 AM") {
                AuraPill("Live", systemImage: "dot.radiowaves.left.and.right", emphasis: .accent)
            }
        }
    }
    .padding()
    .background(Color.background)
    .preferredColorScheme(.dark)
}

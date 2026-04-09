import SwiftUI

enum AuraUntrustedValueKind: String, Equatable, Sendable {
    case metadata
    case link
    case scan
    case deepLink

    var title: String {
        switch self {
        case .metadata:
            return "Untrusted metadata"
        case .link:
            return "Untrusted link"
        case .scan:
            return "Untrusted scan"
        case .deepLink:
            return "Untrusted deep link"
        }
    }

    var accessibilityLabel: String {
        "\(title). Treat this value as externally supplied until verified."
    }
}

struct AuraTrustLabel: View {
    let kind: AuraUntrustedValueKind
    @ScaledMetric(relativeTo: .caption) private var iconSize = 10.0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: iconSize, weight: .bold))
                .accessibilityHidden(true)

            Text(kind.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(red: 0.97, green: 0.8, blue: 0.38))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.58, green: 0.37, blue: 0.08).opacity(0.28))
        )
        .overlay {
            Capsule()
                .stroke(Color(red: 0.97, green: 0.8, blue: 0.38).opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.accessibilityLabel)
    }
}

#Preview {
    VStack(spacing: 12) {
        AuraTrustLabel(kind: .metadata)
        AuraTrustLabel(kind: .link)
        AuraTrustLabel(kind: .scan)
        AuraTrustLabel(kind: .deepLink)
    }
    .padding()
    .background(Color.background)
    .preferredColorScheme(.dark)
}

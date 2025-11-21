import SwiftUI

// Spacing tokens for Guest Pass / Entrance section
public enum GPSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

// Text style helpers for Guest Pass / Entrance section
public extension View {
    // Section title (“Guest passes”)
    func gpSectionTitleStyle() -> some View {
        self
            .font(.title3)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .foregroundStyle(Color.white.opacity(0.90))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // Section subtitle
    func gpSectionSubtitleStyle() -> some View {
        self
            .font(.callout)
            .foregroundStyle(Color.white.opacity(0.72))
    }

    // Pill label (all caps)
    func gpPillLabelStyle() -> some View {
        self
            .font(.caption2)
            .fontWeight(.medium)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.85))
    }

    // Card title
    func gpCardTitleStyle() -> some View {
        self
            .font(.title3)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .foregroundStyle(Color.white.opacity(0.96))
    }

    // Card subtitle / one-liner
    func gpCardSubtitleStyle() -> some View {
        self
            .font(.callout)
            .foregroundStyle(Color.white.opacity(0.78))
    }

    // Metadata row
    func gpMetadataStyle() -> some View {
        self
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(Color.white.opacity(0.70))
    }

    // CTA strip text
    func gpCTAStyle() -> some View {
        self
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color.white.opacity(0.94))
    }
}

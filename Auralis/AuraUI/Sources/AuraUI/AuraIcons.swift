import SwiftUI

public enum AuraImageAccessibility {
    case decorative
    case label(LocalizedStringKey)
    case control(label: LocalizedStringKey, hint: LocalizedStringKey? = nil)
}

public struct SystemImage: View {
    private let systemName: String
    private let accessibility: AuraImageAccessibility

    public init(_ systemName: String, accessibility: AuraImageAccessibility = .decorative) {
        self.systemName = systemName
        self.accessibility = accessibility
    }

    @ViewBuilder
    public var body: some View {
        accessibleImage
    }

    @ViewBuilder
    private var image: some View {
        if #available(iOS 26, macOS 26, *) {
            Image(systemName: systemName)
                .symbolColorRenderingMode(.gradient)
        } else {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
        }
    }

    @ViewBuilder
    private var accessibleImage: some View {
        switch accessibility {
        case .decorative:
            image
                .accessibilityHidden(true)
        case .label(let label):
            image
                .accessibilityLabel(label)
        case .control(let label, let hint):
            if let hint {
                image
                    .accessibilityLabel(label)
                    .accessibilityHint(hint)
            } else {
                image
                    .accessibilityLabel(label)
            }
        }
    }
}

public struct PrimaryTextSystemImage: View {
    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct SecondaryTextSystemImage: View {
    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.textSecondary)
    }
}

public struct SecondarySystemImage: View {
    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.secondary)
    }
}

public struct SuccessTextSystemImage: View {
    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.success)
    }
}

public struct AccentTextSystemImage: View {
    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.accent)
    }
}

import SwiftUI

public struct SystemImage: View {
    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    @ViewBuilder
    public var body: some View {
        if #available(iOS 26, macOS 26, *) {
            Image(systemName: systemName)
                .symbolColorRenderingMode(.gradient)
        } else {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
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

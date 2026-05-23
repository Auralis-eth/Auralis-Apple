import SwiftUI

public struct SecondaryText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .foregroundStyle(Color.textSecondary)
    }
}

public struct PrimaryText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct TitleFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct Title2FontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct HeadlineFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct SubheadlineFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
    }
}

public struct FootnoteFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
    }
}

private struct CaptionFontText: View {
    let text: String

    var body: Text {
        Text(text)
            .font(.caption)
    }
}

public struct PrimaryCaptionFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        CaptionFontText(text: text)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct SecondaryCaptionFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        CaptionFontText(text: text)
            .foregroundStyle(Color.textSecondary)
    }
}

public struct ErrorText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        CaptionFontText(text: text)
            .foregroundStyle(Color.error)
    }
}

public struct SuccessText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        CaptionFontText(text: text)
            .foregroundStyle(Color.success)
    }
}

public struct Caption2FontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.textPrimary)
    }
}

public struct CalloutFontText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Text {
        Text(text)
            .font(.callout)
            .foregroundStyle(Color.textSecondary)
    }
}

@available(*, deprecated, message: "Use ScaledSystemFontText or semantic text styles so text follows Dynamic Type.")
public struct SystemFontText: View {
    private let text: String
    private let size: CGFloat
    private let weight: Font.Weight?

    public init(text: String, size: CGFloat, weight: Font.Weight? = nil) {
        self.text = text
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        ScaledSystemFontText(text: text, size: size, weight: weight)
    }
}

public struct ScaledSystemFontText: View {
    private let text: String
    private let weight: Font.Weight?
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 17

    public init(text: String, size: CGFloat, weight: Font.Weight? = nil) {
        self.text = text
        self.weight = weight
        self._scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    public var body: Text {
        Text(text)
            .font(.system(size: scaledSize, weight: weight))
            .foregroundStyle(Color.textPrimary)
    }
}

public struct PrimaryTextButton: View {
    private let text: String
    private let action: () -> Void

    public init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PrimaryText(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.deepBlue)
                .clipShape(.rect(cornerRadius: 8))
        }
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension Color {
    static func rgbaComponents(from hex: String) -> (red: UInt64, green: UInt64, blue: UInt64, alpha: UInt64)? {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: cleanedHex).scanHexInt64(&value) else {
            return nil
        }

        switch cleanedHex.count {
        case 3:
            return (
                red: (value >> 8) * 17,
                green: (value >> 4 & 0xF) * 17,
                blue: (value & 0xF) * 17,
                alpha: 255
            )
        case 6:
            return (
                red: value >> 16,
                green: value >> 8 & 0xFF,
                blue: value & 0xFF,
                alpha: 255
            )
        case 8:
            return (
                red: value >> 24,
                green: value >> 16 & 0xFF,
                blue: value >> 8 & 0xFF,
                alpha: value & 0xFF
            )
        default:
            return nil
        }
    }

    init(hexString hex: String) {
        let components = Self.rgbaComponents(from: hex) ?? (red: 1, green: 1, blue: 1, alpha: 0)

        self.init(
            .sRGB,
            red: Double(components.red) / 255,
            green: Double(components.green) / 255,
            blue: Double(components.blue) / 255,
            opacity: Double(components.alpha) / 255
        )
    }

    static let deepBlue = Color(hexString: "012348")
    static let auraSecondary = Color(hexString: "00C690")
    static let accent = Color(hexString: "7751A9")
    static let background = Color(hexString: "121212")
    static let surface = Color(hexString: "1E1E1E")
    static let textPrimary = Color(hexString: "FFFFFF")
    static let textSecondary = Color(hexString: "BDBDBD")
    static let error = Color(hexString: "FF3B30")
    static let success = Color(hexString: "4CD964")
    static let separator = Color(hexString: "FFFFFF2E")
    static let auroraGreen = Color(hexString: "39FF14")
    static let auroraCyan = Color(hexString: "00FFFF")
    static let auroraPurple = Color(hexString: "BF00FF")
    static let auroraPink = Color(hexString: "FF1493")
    static let auroraBlue = Color(hexString: "1E90FF")
    static let auroraTeal = Color(hexString: "00FFA5")
}

public extension String {
    func toColor() -> Color {
        toAuraColor()
    }

    func toAuraColor() -> Color {
        let hex = hasPrefix("#") ? String(dropFirst()) : self

        guard let components = Color.rgbaComponents(from: hex) else {
            return .clear
        }

        return Color(
            .sRGB,
            red: Double(components.red) / 255,
            green: Double(components.green) / 255,
            blue: Double(components.blue) / 255,
            opacity: Double(components.alpha) / 255
        )
    }
}

#if canImport(UIKit)
public extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

        let alpha: CGFloat = 1.0
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        switch hex.count {
        case 6:
            red = CGFloat((int >> 16) & 0xFF) / 255
            green = CGFloat((int >> 8) & 0xFF) / 255
            blue = CGFloat(int & 0xFF) / 255
        default:
            return nil
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func contrastRatio(with color: UIColor) -> CGFloat {
        auraContrastRatio(with: color)
    }

    func auraContrastRatio(with color: UIColor) -> CGFloat {
        let luminance1 = auraLuminance
        let luminance2 = color.auraLuminance
        let lighter = max(luminance1, luminance2)
        let darker = min(luminance1, luminance2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var auraLuminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: nil)

        func adjustedColorComponent(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * adjustedColorComponent(red)
            + 0.7152 * adjustedColorComponent(green)
            + 0.0722 * adjustedColorComponent(blue)
    }
}
#endif

//
//  Colour.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import SwiftUI

extension Color {
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
}

// NFTOS App Color Palette
extension Color {
    // MARK: Main colors
    //  for buttons and navigation, with white text for high contrast.
    static let deepBlue = Color(hexString: "012348")       // Deep Blue

    //    for secondary actions, using black text on light buttons for accessibility.
    static let secondary = Color(hexString: "00C690")     // Teal Green

    //    for highlights, ensuring good contrast with white text.
    static let accent = Color(hexString: "7751A9")        // Purple


    // MARK: Background colors
    //    for a sleek, dark mode look, with white text for readability.
    static let background = Color(hexString: "121212")    // Very Dark Gray
    static let surface = Color(hexString: "1E1E1E")       // Dark Gray for cards/modals

    // MARK: Text colors
    //      for main text
    static let textPrimary = Color(hexString: "FFFFFF")   // White

    //      for subtitles
    static let textSecondary = Color(hexString: "BDBDBD") // Light Gray

    // Status colors
    //black text is recommended
    static let error = Color(hexString: "FF3B30")         // Error Red
    static let success = Color(hexString: "4CD964")       // Success Green


//    static let textDark = Color(hexString: "4AD7D1")
    static let auroraGreen = Color(hexString: "39FF14")      // Electric lime green
    static let auroraCyan = Color(hexString: "00FFFF")       // Bright cyan
    static let auroraPurple = Color(hexString: "BF00FF")     // Vivid purple
    static let auroraPink = Color(hexString: "FF1493")       // Deep pink
    static let auroraBlue = Color(hexString: "1E90FF")       // Bright blue
    static let auroraTeal = Color(hexString: "00FFA5")       // Bright teal
}

extension String {
    func toColor() -> Color {
        let hex = self.hasPrefix("#") ? String(dropFirst()) : self

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

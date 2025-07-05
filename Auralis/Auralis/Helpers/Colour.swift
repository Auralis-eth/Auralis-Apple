//
//  Colour.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import SwiftUI

extension Color {
    init(hexString hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
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

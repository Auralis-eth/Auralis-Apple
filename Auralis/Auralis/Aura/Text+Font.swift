//
//  Text+Font.swift
//  Auralis
//
//  Created by Daniel Bell on 5/1/25.
//

import SwiftUI

struct SecondaryText: View {
    let text: String
    var body: Text {
        Text(text)
            .foregroundStyle(Color.textSecondary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct PrimaryText: View {
    let text: String
    var body: Text {
        Text(text)
            .foregroundStyle(Color.textPrimary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct TitleFontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
    }
}

struct Title2FontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct HeadlineFontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.textPrimary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct SubheadlineFontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct FootnoteFontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
    }
    init(_ text: String) {
        self.text = text
    }
}

fileprivate struct CaptionFontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.caption)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct PrimaryCaptionFontText: View {
    let text: String
    var body: some View {
        CaptionFontText(text)
            .foregroundStyle(Color.textPrimary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct SecondaryCaptionFontText: View {
    let text: String
    var body: some View {
        CaptionFontText(text)
            .foregroundStyle(Color.textSecondary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct ErrorText: View {
    let text: String
    var body: some View {
        CaptionFontText(text)
            .foregroundStyle(Color.error)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct SuccessText: View {
    let text: String
    var body: some View {
        CaptionFontText(text)
            .foregroundStyle(Color.success)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct Caption2FontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.textPrimary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct CalloutFontText: View {
    let text: String
    var body: Text {
        Text(text)
            .font(.callout)
            .foregroundStyle(Color.textSecondary)
    }
    init(_ text: String) {
        self.text = text
    }
}

struct SystemFontText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight? = nil
    var body: Text {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Color.textPrimary)
    }
}



struct PrimaryTextButton: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PrimaryText(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.deepBlue)
                .cornerRadius(8)
        }
    }

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }
}

struct SystemImage: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .symbolColorRenderingMode(.gradient)
//            .resizable()
    }
    init(_ systemName: String) {
        self.systemName = systemName
    }
}

struct PrimaryTextSystemImage: View {
    let systemName: String
    var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.textPrimary)
    }
    init(_ systemName: String) {
        self.systemName = systemName
    }
}

struct SecondaryTextSystemImage: View {
    let systemName: String
    var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.textSecondary)
    }
    init(_ systemName: String) {
        self.systemName = systemName
    }
}

struct SecondarySystemImage: View {
    let systemName: String
    var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.secondary)
    }
    init(_ systemName: String) {
        self.systemName = systemName
    }
}


struct SuccessTextSystemImage: View {
    let systemName: String
    var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.success)
    }
    init(_ systemName: String) {
        self.systemName = systemName
    }
}

struct AccentTextSystemImage: View {
    let systemName: String
    var body: some View {
        SystemImage(systemName)
            .foregroundStyle(Color.accent)
    }
    init(_ systemName: String) {
        self.systemName = systemName
    }
}


import AuraUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct GuestPassCard: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let account: GuestPassAccount
    private var onTap: (() -> Void)?

    @State private var isAnimating = false

    public init(account: GuestPassAccount, onTap: (() -> Void)? = nil) {
        self.account = account
        self.onTap = onTap
    }

    private var shortAddress: String {
        let trimmed = account.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed.prefix(6)
        let end = trimmed.suffix(4)
        return "\(start)...\(end)"
    }

    private var needsOpaqueSurface: Bool {
        accessibilityReduceTransparency || colorSchemeContrast == .increased
    }

    private var shouldAnimateBorder: Bool {
        !accessibilityReduceMotion && !accessibilityReduceTransparency
    }

    private var motionPolicy: AuraMotionPolicy {
        AuraMotionPolicy(reduceMotion: accessibilityReduceMotion)
    }

    public var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.title)
        .accessibilityValue(
            String(localized: "\(account.subtitle). Ethereum address \(account.address.auraGroupedForSpeech)")
        )
        .accessibilityHint(
            String(localized: "Opens Auralis with this guest pass account."),
            isEnabled: onTap != nil
        )
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction(named: String(localized: "Copy address")) {
            copyAddress()
        }
        .onChange(of: shouldAnimateBorder, initial: true) { _, shouldAnimate in
            guard shouldAnimate else {
                isAnimating = false
                return
            }

            if !isAnimating {
                withAnimation(motionPolicy.decorativeLoop) {
                    isAnimating = true
                }
            }
        }
    }

    private func copyAddress() {
        #if canImport(UIKit)
        UIPasteboard.general.string = account.address
        #endif
        AuraAccessibilityAnnouncer.announce(String(localized: "Address copied"))
    }

    private var cardContent: some View {
        VStack {
            HStack(alignment: .center) {
                SystemImage(account.roleImage)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                Spacer()
                if let ens = account.ens {
                    Caption2FontText(ens.uppercased())
                        .textCase(.uppercase)
                        .monospaced()
                }
                Spacer()

                HStack {
                    ForEach(account.metadata) { metadata in
                        SystemImage(metadata.systemImage)
                            .font(.footnote)
                            .foregroundStyle(Color.textPrimary.opacity(0.75))
                            .accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(Color.textPrimary.opacity(0.85))
            .padding(.top, 20)
            .padding(.horizontal, 24)

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Text(account.title)
                    .font(.title3)
                    .fontWeight(.black)
                    .monospaced()
                    .tracking(dynamicTypeSize.isAccessibilitySize ? 0 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textPrimary)

                Text(account.subtitle)
                    .font(.subheadline)
                    .fontWeight(.thin)
                    .monospaced()
                    .tracking(dynamicTypeSize.isAccessibilitySize ? 0 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ADDRESS")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                    Text(shortAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                SystemImage("barcode")
                    .font(.system(size: 40, weight: .black))
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 30)
            .padding(.horizontal, 24)
        }
        .auraSurfaceBackground(style: .regular, cornerRadius: 30)
        .overlay {
            if shouldAnimateBorder && !needsOpaqueSurface {
                GeometryReader { geometry in
                    let maskSide = max(geometry.size.width, geometry.size.height) * 1.6
                    let travel = max(geometry.size.width, geometry.size.height) * 0.35

                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30)
                                .stroke(
                                    LinearGradient(
                                        colors: [.clear, .accent.opacity(0.8), .white, .accent.opacity(0.8), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .mask(
                                    LinearGradient(
                                        colors: [.clear, .black, .clear],
                                        startPoint: isAnimating ? .topLeading : .bottomTrailing,
                                        endPoint: isAnimating ? .bottomTrailing : .topLeading
                                    )
                                    .frame(width: maskSide, height: maskSide)
                                    .offset(x: isAnimating ? travel : -travel, y: isAnimating ? travel : -travel)
                                )
                        )
                }
            }
        }
        .overlay {
            if !needsOpaqueSurface {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
                    .blendMode(.overlay)
                    .blur(radius: 1)
            }
        }
        .shadow(color: needsOpaqueSurface ? .clear : .accent.opacity(0.4), radius: 20, x: 0, y: 10)
        .contentShape(.rect)
    }
}

import AuraUI
import SwiftUI

public struct GuestPassCard: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .onChange(of: accessibilityReduceMotion, initial: true) { _, reduceMotion in
            guard reduceMotion else {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
                return
            }

            isAnimating = false
        }
    }

    private var cardContent: some View {
        VStack {
            HStack(alignment: .center) {
                SystemImage(account.roleImage)
                    .font(.system(size: 20))
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
                    .tracking(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textPrimary)

                Text(account.subtitle)
                    .font(.subheadline)
                    .fontWeight(.thin)
                    .monospaced()
                    .tracking(2)
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
                        .foregroundStyle(.white.opacity(0.5))
                    Text(shortAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityLabel("Ethereum address \(account.address)")
                }

                Spacer()

                SystemImage("barcode")
                    .font(.system(size: 40, weight: .black))
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.bottom, 30)
            .padding(.horizontal, 24)
        }
        .auraSurfaceBackground(style: .regular, cornerRadius: 30)
        .overlay {
            if !needsOpaqueSurface {
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

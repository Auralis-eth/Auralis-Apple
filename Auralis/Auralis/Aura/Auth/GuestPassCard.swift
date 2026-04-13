import SwiftUI

struct GuestPassCard: View {
    let account: GuestPassAccount
    var onTap: (() -> Void)? = nil

    @State private var isAnimating = false

    private var shortAddress: String {
        let trimmed = account.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed.prefix(6)
        let end = trimmed.suffix(4)
        return "\(start)…\(end)"
    }

    var body: some View {
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
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }

    private var cardContent: some View {
        VStack {
            HStack(alignment: .center) {
                SystemImage(account.role.image)
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
        .background {
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
        }
        .overlay {
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
                            .frame(width: 800, height: 800)
                            .offset(x: isAnimating ? 200 : -200, y: isAnimating ? 200 : -200)
                        )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.5), lineWidth: 1)
                .blendMode(.overlay)
                .blur(radius: 1)
        }
        .shadow(color: .accent.opacity(0.4), radius: 20, x: 0, y: 10)
        .contentShape(.rect)
    }
}

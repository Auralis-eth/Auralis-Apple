//
//  AddressEntryView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI
import SwiftData
// Uses GPSpacing & typography helpers from GuestPassTokens.swift

struct AddressInputView: View {
    @State private var address: String = ""
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?

    struct DemoAccount: Identifiable, Hashable {
        var id: String {
            address
        }
        let address: String
        let title: String
        let subtitle: String
    }

    private let demoAccounts: [DemoAccount] = [
        DemoAccount(
            address: "0x9266f125fb2ecb730d9953b46de9c32e2fa83e4a",
            title: "Coop Records (cooprecords.eth)",
            subtitle: "Modern music label with on-chain collection"
        ),
        DemoAccount(
            address: "0x5b93ff82faaf241c15997ea3975419dddd8362c5",
            title: "Coopahtroopa (coopahtroopa.eth)",
            subtitle: "Collector of many notable music NFTs"
        ),
        DemoAccount(
            address: "0x86e2a5a7176a3ff9079e41363d9160b80d0b8134",
            title: "Catalog Records Treasury",
            subtitle: "Label vault focused on unique 1-of-1s"
        ),
        DemoAccount(
            address: "0x8fa39d1db57f95a79e45c0663efd09ba17f7ea5b",
            title: "Sound Protocol Treasury",
            subtitle: "Big Sound.xyz editions and protocol mints"
        ),
        DemoAccount(
            address: "0xd08b97329d7Ef689E71d384c4E5001952Dd15b00",
            title: "Good Karma Records DAO (goodkarmarecords.eth)",
            subtitle: "Community label wallet with shared splits"
        ),
        DemoAccount(
            address: "0xb1adceddb2941033a090dd166a62b6317d5a3b94",
            title: "10:22PM / KINGSHIP (UMG)",
            subtitle: "Major label project with Bored Ape band"
        )
    ]

    private func selectDemo(address: String) {
        self.address = address
        handleSubmit()
    }

    private var isAddressValid: Bool {
        extractEthereumAddress(address) != nil
    }

    var body: some View {
        VStack(alignment: .center) {
            // Header
            VStack(spacing: 6) {
                Title2FontText("Check in with your Ethereum address")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                SubheadlineFontText("Paste an address or ENS name, or scan a QR code to get started.")
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                QRScannerView(account: $currentAccount)
                    .transition(.opacity)
                AddressTextField(address: $address)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 18)

            Button {
                handleSubmit()
            } label: {
                Text("Enter Auralis")
                    .foregroundStyle(Color.textPrimary)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.accent.gradient, in: .capsule)
            }
            .padding(.horizontal, 30)

            HStack {
                Rectangle()
                    .fill(Color.textSecondary.opacity(0.2))
                    .frame(width: 72, height: 1)
                SubheadlineFontText("Or explore Auralis as a guest")
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle()
                    .fill(Color.textSecondary.opacity(0.2))
                    .frame(width: 72, height: 1)
            }
            .padding(.vertical)
            VStack(spacing: 6) {
                Text("Guest passes").gpSectionTitleStyle().multilineTextAlignment(.center)

                Text("Try Auralis with curated public collections.").gpSectionSubtitleStyle().multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)

            GuestPassCarousel(items: demoAccounts, select: { acct in
                selectDemo(address: acct.address)
            })
            .padding(.bottom, GPSpacing.s)

        }
        .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 30))
        .safeAreaPadding(15)
        .transition(.scale.combined(with: .opacity))
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .submitLabel(.go)
        .onSubmit {
            handleSubmit()
        }
    }

    private func handleSubmit() {
        guard !address.isEmpty else {
            showAlert(title: "Address Required",
                      message: "Please enter your Ethereum address or use a guest pass.")
            return
        }

        guard let normalized = extractEthereumAddress(address) else {
            showAlert(title: "Invalid Address",
                      message: "That doesn’t look like a valid address or ENS. Try again or use a guest pass.")
            return
        }

        let eoAccount = EOAccount(address: normalized, access: .readonly)
        modelContext.insert(eoAccount)
        do {
            try modelContext.save()
            address = ""
            currentAccount = eoAccount
        } catch {
            showAlert(title: "Save Failed",
                      message: "Failed to save account: \(error.localizedDescription)")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    private func extractEthereumAddress(_ input: String) -> String? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        let addressPattern = #"^0x[a-fA-F0-9]{40}$"#
        if let match = address.range(of: addressPattern, options: .regularExpression) {
            return String(address[match])
        }
        // If the input is a 40-character hex string without the 0x prefix, prepend it and accept.
        let noPrefixPattern = #"^[a-fA-F0-9]{40}$"#
        if let match = address.range(of: noPrefixPattern, options: .regularExpression) {
            return "0x" + String(address[match])
        }
        return nil
    }
}

struct AddressTextField: View {
    @Binding var address: String

    var body: some View {
        TextField(
            "Ethereum Address",
            text: $address,
            prompt: Text("0x… or ENS name").foregroundColor(.textSecondary)
        )
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.body)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.textSecondary)
    }
}

struct GuestPassCarousel: View {
    let items: [AddressInputView.DemoAccount]
    let select: (AddressInputView.DemoAccount) -> Void

    @State private var currentIndex: Int? = 0

    var body: some View {
        VStack(spacing: GPSpacing.m) {
            ScrollView(.horizontal) {
                HStack(spacing: GPSpacing.m) {
                    ForEach(items) { acct in
                        Button {
                            select(acct)
                        } label: {
                            GuestPassCardView(
                                pillLeft: "LABEL",
                                ensRight: extractENS(from: acct.title),
                                title: stripENS(from: acct.title),
                                subtitle: acct.subtitle,
                                metadata: [
                                    MetadataChunk(systemImage: "music.note", text: "Public collection"),
                                    MetadataChunk(systemImage: "link", text: "Ethereum")
                                ],
                                ctaTitle: "Start with \(stripENS(from: acct.title)) ▸",
                                brandColor: .accentColor
                            )
                            .id(acct)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(acct.title))
                        .accessibilityHint(Text("Opens Auralis with a demo account"))
                    }
                }
                .scrollTargetLayout()
                .contentMargins(.horizontal, GPSpacing.xl, for: .scrollContent)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentIndex)

            // Page indicator
            HStack(spacing: GPSpacing.s) {
                ForEach(items.indices, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentIndex ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.6), lineWidth: idx == currentIndex ? 0 : 1)
                        )
                }
            }
            .padding(.top, GPSpacing.s)
        }
    }
}

// MARK: - Guest Pass Card Support

struct MetadataChunk: Identifiable {
    let id = UUID()
    let systemImage: String
    let text: String
}

private func extractENS(from title: String) -> String? {
    // Extracts text within parentheses e.g., "Coop Records (cooprecords.eth)" -> "cooprecords.eth"
    guard let open = title.firstIndex(of: "("), let close = title.firstIndex(of: ")"), open < close else {
        return nil
    }
    let ens = title[title.index(after: open)..<close]
    return String(ens)
}

private func stripENS(from title: String) -> String {
    // Removes parenthetical ENS from title for cleaner display
    guard let open = title.firstIndex(of: "("), let close = title.firstIndex(of: ")"), open < close else {
        return title
    }
    var base = title
    base.removeSubrange(open...close)
    return base.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct GuestPassCardView: View {
    let pillLeft: String
    let ensRight: String?
    let title: String
    let subtitle: String
    let metadata: [MetadataChunk]
    let ctaTitle: String
    let brandColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content area
            VStack(alignment: .leading, spacing: 0) {
                // Pill row
                HStack {
                    Text(pillLeft)
                        .gpPillLabelStyle()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(brandColor.opacity(0.30))
                        .clipShape(Capsule())
                    Spacer()
                    if let ens = ensRight {
                        Text(ens)
                            .gpPillLabelStyle()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, GPSpacing.s)

                // Title
                Text(title)
                    .gpCardTitleStyle()
                    .lineLimit(2)
                    .padding(.bottom, GPSpacing.xs)

                // Subtitle
                Text(subtitle)
                    .gpCardSubtitleStyle()
                    .lineLimit(3)
                    .padding(.bottom, GPSpacing.m)

                // Metadata row
                if !metadata.isEmpty {
                    HStack(spacing: GPSpacing.s) {
                        ForEach(metadata) { md in
                            HStack(spacing: 6) {
                                Image(systemName: md.systemImage)
                                Text(md.text)
                            }
                            .gpMetadataStyle()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, GPSpacing.m)
                }
            }
            .padding(.horizontal, GPSpacing.l)
            .padding(.top, GPSpacing.m)

            // CTA strip (min 44 pt height)
            HStack {
                Spacer()
                Text(ctaTitle)
                    .gpCTAStyle()
                Spacer()
            }
            .frame(minHeight: 44)
            .padding(.vertical, 4)
            .padding(.horizontal, GPSpacing.l)
            .background(brandColor.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, GPSpacing.l)
            .padding(.bottom, GPSpacing.m)
        }
        .background(Color.surface.opacity(0.75), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.textSecondary.opacity(0.12))
        )
        .shadow(color: brandColor.opacity(0.35), radius: 12, x: 0, y: 6) // soft glow
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

//struct DemoAccountChip: View {
//    let title: String
//    let subtitle: String
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: GPSpacing.s) {
//            Text(title)
//                .gpCardTitleStyle()
//                .lineLimit(2)
//                .multilineTextAlignment(.leading)
//                .padding(.bottom, GPSpacing.xs)
//
//            Text(subtitle)
//                .gpCardSubtitleStyle()
//                .lineLimit(3)
//                .multilineTextAlignment(.leading)
//        }
//        .padding(.horizontal, GPSpacing.l)
//        .padding(.vertical, GPSpacing.m)
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .background(Color.surface.opacity(0.75), in: .rect(cornerRadius: 14))
//        .overlay(
//            RoundedRectangle(cornerRadius: 14)
//                .stroke(Color.textSecondary.opacity(0.12))
//        )
//        .contentShape(.rect)
//    }
//}

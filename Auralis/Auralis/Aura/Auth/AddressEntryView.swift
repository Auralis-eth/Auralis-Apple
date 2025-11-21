//
//  AddressEntryView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI
import SwiftData

struct AddressInputView: View {
    @State private var address: String = ""
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?

    private struct DemoAccount: Identifiable {
        let id = UUID()
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
                Title2FontText("Guest passes")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                SubheadlineFontText("Try Auralis with curated public collections.")
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(demoAccounts) { acct in
                    Button {
                        selectDemo(address: acct.address)
                    } label: {
                        DemoAccountChip(title: acct.title, subtitle: acct.subtitle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(acct.title))
                    .accessibilityHint(Text("Opens Auralis with a demo account"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

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

struct DemoAccountChip: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface.opacity(0.75), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.textSecondary.opacity(0.12))
        )
        .contentShape(.rect)
    }
}


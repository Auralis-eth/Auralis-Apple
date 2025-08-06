//
//  AddressEntryView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI
import SwiftData

struct AddressEntryView: View {
    @State private var address: String = ""
    @State private var showingAlert: Bool = false
    @State private var isAddressValid: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?

    var body: some View {
            // Bottom form section
        Group {
            VStack {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.deepBlue)
                        .font(.system(size: 30, weight: .medium))
                    TextField("Ethereum Address", text: $address)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.body)  // Use your desired font
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Color.surface)
                        .onChange(of: address) { _, newValue in
                            validateAddress(newValue)
                        }

                    QRScannerView(account: $currentAccount)
                        .transition(.opacity)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 18)

                Button {
                    // Handle sign in action
                    guard address.isEmpty == false else {
                        showingAlert = true
                        return
                    }

                    validateAddress(address)

                    guard isAddressValid else {
                        showingAlert = true
                        return
                    }

                    let eoAccount = EOAccount(address: address, access: .readonly)
                    self.currentAccount = eoAccount
                    modelContext.insert(eoAccount)
                    try? modelContext.save()
                    self.address = ""
                } label: {
                    Text("View Assets")
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.accent.gradient, in: .capsule)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 18)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
            .safeAreaPadding(15)
            .transition(.scale.combined(with: .opacity))
        }
        .alert("Address Required", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter your Address to continue.")
        }

    }
    private func validateAddress(_ address: String) {
        // Simple validation - should be 42 chars with 0x prefix
        isAddressValid = extractEthereumAddress(address) != nil
    }
    private func extractEthereumAddress(_ input: String) -> String? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }

        // Use regular expression to match Ethereum address pattern
        let addressPattern = #"^0x[a-fA-F0-9]{40}$"#

        if let match = address.range(of: addressPattern, options: .regularExpression) {
            return String(address[match])
        }

        return nil
    }
}

//import ImagePlayground
//@available(iOS 18.4, *)
//func generateImageFromPlayground() async throws {
//    let seletedStyle: ImagePlaygroundStyle = .animation
//    let creator = try await ImageCreator()
//    let images = creator.images(for: [.text("Aurora Borealis over the Arctic and Rocky Mounts")], style: seletedStyle, limit: 4)
//
//    for try await image in images {
//        print("Generated image:")
//        print(image.cgImage)
//    }
//}

// TIPS
//      Break down the process/request

//  USE CASES
//      Content Generation???
//          splash image
//      summarization
//          in the NFT newsfeed view summarize NFT text blurb
//      In-app  user guides
//          have a ? button on each screen and do a help bot
//      Classification
//          start with the "stash" page for NFTs, then migrate to ERC-20s
//      Tag generation
//          start with the "stash" page for NFTs, then migrate to ERC-20s


//      Composition???
//          what is it and could I use it
//      Revision???
//          what is it and could I use it

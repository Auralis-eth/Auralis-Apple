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

    var body: some View {
        AddressEntryContentView(
            address: $address,
            currentAccount: $currentAccount,
            handleSubmit: handleSubmit,
            selectDemo: selectDemo
        )
        .glassEffect(.clear.tint(.surface), in: .containerRelative)
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

    private func selectDemo(address: String) {
        self.address = address
        handleSubmit(source: .guestPass)
    }

    private func handleSubmit() {
        handleSubmit(source: .manualEntry)
    }

    private func handleSubmit(source: EOAccountSource) {
        guard !address.isEmpty else {
            showAlert(title: "Address Required",
                      message: "Please enter your Ethereum address or use a guest pass.")
            return
        }

        let store = AccountStore(modelContext: modelContext)

        guard store.normalizeAddress(address) != nil else {
            showAlert(title: "Invalid Address",
                      message: "That doesn’t look like a valid address or ENS. Try again or use a guest pass.")
            return
        }

        do {
            let activation = try store.activateWatchAccount(
                from: address,
                source: source
            )
            address = ""
            currentAccount = activation.account

            if !activation.wasCreated {
                showAlert(
                    title: "Account Already Added",
                    message: "Switched to the existing saved account for that address."
                )
            }
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
}

private struct AddressEntryContentView: View {
    @Binding var address: String
    @Binding var currentAccount: EOAccount?
    let handleSubmit: () -> Void
    let selectDemo: (String) -> Void

    var body: some View {
        VStack(alignment: .center) {
            // Header
            AddressEntryHeaderView()
            
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
            
            GuestExploreDividerView()
            GuestPassesHeaderView()
            GuestPassCarousel(items: DemoAccount.accounts) { acct in
                selectDemo(acct.address)
            }
        }
    }
}


struct AddressEntryHeaderView: View {
    var body: some View {
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
    }
}

struct GuestExploreDividerView: View {
    var body: some View {
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
    }
}

struct GuestPassesHeaderView: View {
    var body: some View {
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
    }
}

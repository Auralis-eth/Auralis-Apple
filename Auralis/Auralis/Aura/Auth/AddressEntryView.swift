//
//  AddressEntryView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI
import SwiftData
import UIKit

struct AddressInputView: View {
    @State private var address: String = ""
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]
    @Binding var currentAccount: EOAccount?

    private var validationResult: AccountAddressValidationResult {
        AccountStore.validateAddressInput(address)
    }

    private var validationMessage: String? {
        switch validationResult {
        case .empty, .valid:
            return nil
        case .unsupportedENS, .invalidFormat:
            return validationResult.userFacingMessage
        }
    }

    private var normalizedAddress: String? {
        validationResult.normalizedAddress
    }

    var body: some View {
        AddressEntryContentView(
            address: $address,
            currentAccount: $currentAccount,
            validationMessage: validationMessage,
            normalizedAddress: normalizedAddress,
            handleSubmit: handleSubmit,
            selectDemo: selectDemo
        )
        .glassEffect(.clear.tint(.surface), in: .containerRelative)
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
        switch validationResult {
        case .empty:
            showAlert(title: "Address Required", message: validationResult.userFacingMessage)
            return
        case .unsupportedENS:
            showAlert(title: "ENS Not Supported Yet", message: validationResult.userFacingMessage)
            return
        case .invalidFormat:
            showAlert(title: "Invalid Address", message: validationResult.userFacingMessage)
            return
        case .valid:
            break
        }

        let store = AccountStore(
            modelContext: modelContext,
            eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
        )

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
    let validationMessage: String?
    let normalizedAddress: String?
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

            if let validationMessage {
                ErrorText(validationMessage)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let normalizedAddress {
                VStack(spacing: 10) {
                    SubheadlineFontText("canonical form")
                        .foregroundStyle(Color.textSecondary)

                    Text(normalizedAddress)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.surface.opacity(0.55))
                        )
                }
                .padding(.horizontal, 20)
            }
            
            AuraActionButton("Enter Auralis", style: .hero) {
                handleSubmit()
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
            
            SubheadlineFontText("Paste an EVM wallet address or scan a QR code to get started.")
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct GuestExploreDividerView: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.textSecondary.opacity(0.2))
                .frame(width: 72, height: 1)
                .accessibilityHidden(true)
            SubheadlineFontText("Or explore Auralis as a guest")
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color.textSecondary.opacity(0.2))
                .frame(width: 72, height: 1)
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
    }
}

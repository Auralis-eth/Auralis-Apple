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
    private struct PendingENSMappingChange: Identifiable, Equatable {
        let id = UUID()
        let ensName: String
        let cachedAddress: String
        let resolvedAddress: String
        let source: EOAccountSource
        let correlationID: String
    }

    @State private var address: String = ""
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showingENSMappingChangeAlert: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var activeSubmissionTask: Task<Void, Never>?
    @State private var activeSubmissionID = UUID()
    @State private var pendingENSMappingChange: PendingENSMappingChange?
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]
    @Binding var currentAccount: EOAccount?
    let ensResolver: any ENSResolving

    private var validationResult: AccountAddressValidationResult {
        AccountStore.validateAddressInput(address)
    }

    private var isENSInput: Bool {
        AccountStore.looksLikeENSName(address)
    }

    private var validationMessage: String? {
        if isENSInput {
            return nil
        }

        switch validationResult {
        case .empty, .valid:
            return nil
        case .unsupportedENS, .invalidFormat:
            return validationResult.userFacingMessage
        }
    }

    private var normalizedAddress: String? {
        guard !isENSInput else {
            return nil
        }
        return validationResult.normalizedAddress
    }

    var body: some View {
        AddressEntryContentView(
            address: $address,
            currentAccount: $currentAccount,
            validationMessage: validationMessage,
            normalizedAddress: normalizedAddress,
            isSubmitting: isSubmitting,
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
        .alert("Confirm Updated ENS Mapping", isPresented: $showingENSMappingChangeAlert) {
            Button("Use Updated Address") {
                guard let change = pendingENSMappingChange else {
                    isSubmitting = false
                    return
                }
                confirmENSMappingChange(change)
            }
            Button("Cancel", role: .cancel) {
                isSubmitting = false
                pendingENSMappingChange = nil
            }
        } message: {
            if let change = pendingENSMappingChange {
                Text(
                    "\(change.ensName) moved from \(change.cachedAddress) to \(change.resolvedAddress). Save the updated address?"
                )
            }
        }
        .submitLabel(.go)
        .onSubmit {
            handleSubmit()
        }
        .onDisappear {
            activeSubmissionTask?.cancel()
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
        activeSubmissionTask?.cancel()
        let submissionID = UUID()
        activeSubmissionID = submissionID
        activeSubmissionTask = Task {
            await submit(
                input: address,
                source: source,
                submissionID: submissionID
            )
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    @MainActor
    private func submit(
        input: String,
        source: EOAccountSource,
        submissionID: UUID
    ) async {
        let validationResult = AccountStore.validateAddressInput(input)
        let isENSInput = AccountStore.looksLikeENSName(input)

        switch validationResult {
        case .empty:
            showAlert(title: "Address Required", message: validationResult.userFacingMessage)
            return
        case .invalidFormat:
            if !isENSInput {
                showAlert(title: "Invalid Address", message: validationResult.userFacingMessage)
                return
            }
        case .unsupportedENS, .valid:
            break
        }

        let store = AccountStore(
            modelContext: modelContext,
            eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
        )
        let correlationID = UUID().uuidString

        do {
            isSubmitting = true
            let activation: AccountActivationResult

            if isENSInput {
                let resolution = try await ensResolver.resolveAddress(
                    forENS: input,
                    correlationID: correlationID
                )
                guard submissionID == activeSubmissionID else {
                    return
                }
                activation = try store.activateWatchAccount(
                    from: resolution.address,
                    name: resolution.ensName,
                    source: source,
                    correlationID: correlationID
                )
            } else {
                guard submissionID == activeSubmissionID else {
                    return
                }
                activation = try store.activateWatchAccount(
                    from: input,
                    source: source,
                    correlationID: correlationID
                )
            }

            guard submissionID == activeSubmissionID else {
                return
            }
            address = ""
            currentAccount = activation.account
            isSubmitting = false
            activeSubmissionTask = nil

            if !activation.wasCreated {
                showAlert(
                    title: "Account Already Added",
                    message: "Switched to the existing saved account for that address."
                )
            }
        } catch let error as ENSResolutionError {
            guard submissionID == activeSubmissionID else {
                return
            }
            activeSubmissionTask = nil

            switch error {
            case .mappingChanged(let ensName, let cachedAddress, let resolvedAddress):
                pendingENSMappingChange = PendingENSMappingChange(
                    ensName: ensName,
                    cachedAddress: cachedAddress,
                    resolvedAddress: resolvedAddress,
                    source: source,
                    correlationID: correlationID
                )
                showingENSMappingChangeAlert = true
            default:
                isSubmitting = false
                showAlert(
                    title: "Save Failed",
                    message: "Failed to save account: \(error.localizedDescription)"
                )
            }
        } catch is CancellationError {
            if submissionID == activeSubmissionID {
                isSubmitting = false
                activeSubmissionTask = nil
            }
        } catch {
            guard submissionID == activeSubmissionID else {
                return
            }
            activeSubmissionTask = nil
            isSubmitting = false
            showAlert(
                title: "Save Failed",
                message: "Failed to save account: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func confirmENSMappingChange(_ change: PendingENSMappingChange) {
        let store = AccountStore(
            modelContext: modelContext,
            eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
        )

        do {
            let activation = try store.activateWatchAccount(
                from: change.resolvedAddress,
                name: change.ensName,
                source: change.source,
                correlationID: change.correlationID
            )
            address = ""
            currentAccount = activation.account
            isSubmitting = false
            activeSubmissionTask = nil
            pendingENSMappingChange = nil

            if !activation.wasCreated {
                showAlert(
                    title: "Account Already Added",
                    message: "Switched to the existing saved account for that address."
                )
            }
        } catch {
            isSubmitting = false
            pendingENSMappingChange = nil
            showAlert(
                title: "Save Failed",
                message: "Failed to save account: \(error.localizedDescription)"
            )
        }
    }
}

private struct AddressEntryContentView: View {
    @Binding var address: String
    @Binding var currentAccount: EOAccount?
    let validationMessage: String?
    let normalizedAddress: String?
    let isSubmitting: Bool
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
            .disabled(isSubmitting)
            .padding(.horizontal, 30)

            if isSubmitting {
                ProgressView("Resolving account…")
                    .tint(Color.textPrimary)
                    .padding(.top, 8)
            }
            
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
            
            SubheadlineFontText("Paste an EVM wallet address, enter an ENS name, or scan a QR code to get started.")
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

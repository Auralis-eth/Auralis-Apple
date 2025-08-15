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

    private var isAddressValid: Bool {
        extractEthereumAddress(address) != nil
    }

    var body: some View {
        VStack(alignment: .center) {
            HStack {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.textSecondary)
                    .font(.system(size: 30, weight: .medium))
                AddressTextField(address: $address)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 18)

            Button {
                handleSubmit()
            } label: {
                Text("View Assets")
                    .foregroundStyle(Color.textPrimary)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.accent.gradient, in: .capsule)
            }
            .padding(.horizontal, 30)

            QRScannerView(account: $currentAccount)
                .transition(.opacity)
                .padding(.vertical, 18)
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
                      message: "Please enter your Ethereum address.")
            return
        }

        guard isAddressValid else {
            showAlert(title: "Invalid Address",
                      message: "The address you entered is not a valid Ethereum address.")
            return
        }

        let eoAccount = EOAccount(address: address, access: .readonly)
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
        return nil
    }
}

struct AddressTextField: View {
    @Binding var address: String

    var body: some View {
        TextField(
            "Ethereum Address",
            text: $address,
            prompt: Text("Ethereum Address").foregroundColor(.textSecondary)
        )
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.body)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.textSecondary)
    }
}

//
//  QRScannerView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import CodeScanner
import SwiftUI
import SwiftData

struct QRScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isScanning = false
    @State private var torchOn = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @Binding var account: EOAccount?

    var body: some View {
        Button {
            isScanning = true
        } label: {
            SystemImage("qrcode.viewfinder")
                .foregroundStyle(Color.accent)
                .font(.system(size: 30, weight: .medium))
                .accessibilityLabel("Scan wallet QR code")
        }
        .sheet(isPresented: $isScanning) {
            ZStack(alignment: .top) {
                CodeScannerView(codeTypes: [.qr], requiresPhotoOutput: false, isTorchOn: torchOn, completion: handleScan)
                .ignoresSafeArea()

                TorchToggleButton(torchOn: $torchOn)
                    .padding(.top)
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func handleScan(_ result: Result<ScanResult, ScanError>) {
        defer { isScanning = false }

        switch result {
        case .success(let code):
            do {
                let store = AccountStore(
                    modelContext: modelContext,
                    eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
                )
                let activation = try store.activateWatchAccount(
                    from: code.string,
                    source: .qrScan
                )
                account = activation.account

                if !activation.wasCreated {
                    showAlert(
                        title: "Account Already Added",
                        message: "Switched to the existing saved account for that scanned address."
                    )
                }
            } catch {
                showAlert(
                    title: "Scan Failed",
                    message: error.localizedDescription
                )
            }
        case .failure(let error):
            showAlert(
                title: "Scan Failed",
                message: error.localizedDescription
            )
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

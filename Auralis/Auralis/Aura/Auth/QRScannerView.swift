//
//  QRScannerView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import AuralisPrimaryModels
import CodeScanner
import SwiftData
import SwiftUI
import UIKit

@MainActor
enum QRScanValidationOutcome: Equatable {
    case valid
    case alert(title: String, message: String)

    static func classify(_ scannedValue: String) -> QRScanValidationOutcome {
        let validationResult = AccountStore.validateAddressInput(scannedValue)

        switch validationResult {
        case .empty:
            return .alert(title: "Scan Failed", message: validationResult.userFacingMessage)
        case .unsupportedENS:
            return .alert(title: "ENS Not Supported Yet", message: validationResult.userFacingMessage)
        case .invalidFormat:
            return .alert(title: "Scan Failed", message: validationResult.userFacingMessage)
        case .valid:
            return .valid
        }
    }
}

struct QRScannerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.modelContext) private var modelContext
    @State private var isScanning = false
    @State private var torchOn = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    let accountStoreFactory: @MainActor (ModelContext) -> AccountStore
    let onAccountActivated: @MainActor (EOAccount, String?) -> Void

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

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

                VStack(spacing: 12) {
                    AuraTrustLabel(kind: .scan)

                    TorchToggleButton(torchOn: $torchOn)
                }
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
            switch QRScanValidationOutcome.classify(code.string) {
            case .valid:
                break
            case .alert(let title, let message):
                showAlert(title: title, message: message)
                return
            }

            Task {
                let store = accountStoreFactory(modelContext)
                let correlationID = UUID().uuidString
                do {
                    let activation = try await store.activateWatchAccount(
                        from: code.string,
                        source: .qrScan,
                        correlationID: correlationID
                    )
                    onAccountActivated(activation.account, correlationID)
                    haptics.notification(.success)

                    if !activation.wasCreated {
                        showAlert(
                            title: "Account Already Added",
                            message: "Switched to the existing saved account for that scanned address.",
                            feedback: .success
                        )
                    }
                } catch {
                    showAlert(
                        title: "Scan Failed",
                        message: error.localizedDescription
                    )
                }
            }
        case .failure(let error):
            showAlert(
                title: "Scan Failed",
                message: error.localizedDescription
            )
        }
    }

    private func showAlert(
        title: String,
        message: String,
        feedback: UINotificationFeedbackGenerator.FeedbackType = .error
    ) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
        haptics.notification(feedback)
    }
}

import AuraUI
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import WalletAdapters
#if os(iOS)
import CodeScanner
#endif

/// Renders an invite code as a QR image using CoreImage — no external dependency, no camera permission.
enum SocialInviteQR {
    private static let context = CIContext()

    static func image(for code: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale up so the QR is crisp rather than a ~25pt image.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

/// Host/join invite exchange for one shared session (Social v1). Generate produces a shareable code and
/// QR to hand out; join accepts a pasted code or a camera scan. Reachable only when relay social is
/// enabled; otherwise it says so.
struct SocialInviteExchangeView: View {
    @State private var model: SocialInviteExchangeModel
    @State private var pastedCode: String = ""
    @State private var isShowingScanner = false
    private let sessionID: UUID

    init(
        assembly: SocialRelayAssembly,
        participantID: String,
        sessionID: UUID,
        joinVerifier: SocialJoinVerificationService? = nil,
        walletSessionIDProvider: (@Sendable () async -> WalletSessionID?)? = nil
    ) {
        _model = State(initialValue: SocialInviteExchangeModel(
            assembly: assembly,
            participantID: participantID,
            joinVerifier: joinVerifier,
            walletSessionIDProvider: walletSessionIDProvider
        ))
        self.sessionID = sessionID
    }

    /// Convenience initializer from the app composition (`SocialAssembly.makeInviteExchange`).
    init(composition: SocialInviteExchangeComposition, sessionID: UUID) {
        self.init(
            assembly: composition.assembly,
            participantID: composition.participantID,
            sessionID: sessionID,
            joinVerifier: composition.joinVerifier,
            walletSessionIDProvider: composition.walletSessionIDProvider
        )
    }

    var body: some View {
        Form {
            hostSection
            joinSection
            statusSection
        }
        .navigationTitle("Invite")
        .accessibilityIdentifier(A11yID.Social.root)
    }

    @ViewBuilder
    private var hostSection: some View {
        Section("Host") {
            Button("Generate invite") {
                Task { await model.host(sessionID: sessionID) }
            }
            .accessibilityIdentifier(A11yID.Social.generateInvite)
            if let code = model.shareableCode {
                if let cgImage = SocialInviteQR.image(for: code) {
                    Image(decorative: cgImage, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Text(code)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier(A11yID.Social.inviteCode)
                ShareLink(item: code) { Label("Share invite", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier(A11yID.Social.shareInvite)
            }
        }
    }

    @ViewBuilder
    private var joinSection: some View {
        Section("Join") {
            TextField("Paste invite code", text: $pastedCode, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(A11yID.Social.joinCodeField)
            Button("Join") {
                Task { await model.importInvite(code: pastedCode) }
            }
            .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(A11yID.Social.join)

            #if os(iOS)
            Button {
                isShowingScanner = true
            } label: {
                Label("Scan QR", systemImage: "qrcode.viewfinder")
            }
            .accessibilityIdentifier(A11yID.Social.scanInvite)
            .sheet(isPresented: $isShowingScanner) {
                NavigationStack {
                    CodeScannerView(codeTypes: [.qr], scanMode: .once) { result in
                        isShowingScanner = false
                        guard case let .success(scan) = result else { return }
                        Task { await model.importInvite(code: scan.string) }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan invite")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isShowingScanner = false }
                        }
                    }
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .disabled:
            Section {
                Text("Relay social is off in this build.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11yID.Social.status)
            }
        case .hosting:
            Section {
                Label("Hosting — share the invite above.", systemImage: "person.2.wave.2")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11yID.Social.status)
            }
        case let .joined(sessionID, verificationNotice):
            Section {
                Label("Joined session \(sessionID.uuidString).", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier(A11yID.Social.status)
                // The join succeeded; only the optional wallet proof did not. Shown alongside the
                // success rather than replacing it, so the user is not told to re-scan an invite that
                // already worked.
                if let verificationNotice {
                    Label(verificationNotice, systemImage: "person.badge.shield.exclamationmark")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier(A11yID.Social.error)
                }
            }
        case let .failed(message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(A11yID.Social.error)
            }
        }
    }
}

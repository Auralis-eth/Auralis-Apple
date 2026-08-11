import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI
import WalletConnectorKit

struct WalletPickerHostSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
            SortDescriptor(\EOAccount.addedAt, order: .reverse),
            SortDescriptor(\EOAccount.address),
        ]
    ) private var accounts: [EOAccount]

    let onSelectAccount: @MainActor (String) -> Void
    /// An app-lifetime service injected by the host so there is a single live
    /// connector (and a single relay subscription) across launch-time restore and
    /// every picker presentation. When `nil` (e.g. a brand-new user with no
    /// wallets to restore, or previews/tests), the sheet lazily creates its own.
    var walletConnectionService: AuralisWalletConnectionService?

    @State private var service: AuralisWalletConnectionService?

    var body: some View {
        Group {
            if let service {
                WalletPickerSheet(
                    accounts: accounts.filter { $0.source == .walletConnect || $0.access?.canSign == true },
                    service: service,
                    onSelectAccount: onSelectAccount
                )
            } else {
                ProgressView("Loading wallet connector...")
                    .padding(32)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if service == nil {
                service = walletConnectionService ?? AuralisWalletConnectionService(modelContext: modelContext)
            }
        }
    }
}

struct WalletPickerSheet: View {
    let accounts: [EOAccount]
    let service: AuralisWalletConnectionService
    let onSelectAccount: @MainActor (String) -> Void

    @State private var pendingRemoval: EOAccount?
    @State private var signInResult: WalletSignInResult?
    @State private var signingAddress: String?

    private struct WalletSignInResult: Identifiable {
        let id = UUID()
        let message: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                    .blur(radius: isConnecting ? 2 : 0)
                    .disabled(isConnecting)

                if isConnecting {
                    connectionOverlay
                }
            }
            .navigationTitle("Wallets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await service.connectWithQR() }
                    } label: {
                        Image(systemName: "qrcode")
                    }
                    .accessibilityLabel("Show WalletConnect QR code")
                    .accessibilityHint("Creates a generic WalletConnect pairing for any compatible wallet.")
                    .accessibilityIdentifier(A11yID.AuraPlay.walletPickerQR)
                }
            }
            .alert("Remove Wallet?", item: $pendingRemoval) { account in
                Button("Remove", role: .destructive) {
                    Task { await service.remove(account: account) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { account in
                Text("AuraPlay will disconnect \(account.walletDisplayName) and keep local history for future reconnects.")
            }
            .alert("Sign-In with Ethereum", item: $signInResult) { _ in
                Button("OK", role: .cancel) {}
            } message: { result in
                Text(result.message)
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.walletPicker)
    }

    /// Runs a Sign-In with Ethereum challenge for `account` and surfaces the
    /// outcome. `signingAddress` gates the row's spinner/disabled state so a
    /// double-tap can't fire two concurrent challenges for the same wallet.
    private func signIn(_ account: EOAccount) async {
        signingAddress = account.address
        defer { signingAddress = nil }
        do {
            let verified = try await service.signInWithEthereum(account: account)
            signInResult = WalletSignInResult(
                message: verified
                    ? "\(account.walletDisplayName) proved ownership via Sign-In with Ethereum."
                    : "The wallet did not prove ownership of \(account.walletDisplayName)."
            )
        } catch {
            signInResult = WalletSignInResult(message: error.localizedDescription)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if accounts.isEmpty {
                    emptyState
                } else {
                    walletList
                }

                providerList

                if let payload = service.latestPairingPayload {
                    pairingPayloadView(payload)
                }

                if case .failed(let message) = service.phase {
                    errorView(message)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background(Color.background.ignoresSafeArea())
    }

    private var emptyState: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 22) {
            VStack(spacing: 16) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Connect your wallet")
                        .font(.title2.weight(.bold))
                    Text("AuraPlay reads NFTs to build your media library. Your private key is never shared.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await service.connect(with: WalletConnectorCatalog.metamask) }
                } label: {
                    Label("Connect Wallet", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Connect a Web3 wallet to AuraPlay")
                .accessibilityHint("Opens MetaMask when installed, otherwise shows a WalletConnect pairing code.")
                .accessibilityIdentifier(A11yID.AuraPlay.walletPickerConnect)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var walletList: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraSectionHeader(
                title: "Connected Wallets",
                subtitle: "Choose the wallet AuraPlay should use for library discovery."
            )

            VStack(spacing: 10) {
                ForEach(accounts) { account in
                    WalletPickerAccountRow(
                        account: account,
                        isActive: service.activeAddress()?.caseInsensitiveCompare(account.address) == .orderedSame,
                        isSigningIn: signingAddress == account.address,
                        select: {
                            service.setActive(account: account)
                            onSelectAccount(account.address)
                        },
                        remove: {
                            pendingRemoval = account
                        },
                        signIn: account.access?.canSign == true ? { Task { await signIn(account) } } : nil
                    )
                }
            }

            Button {
                Task { await service.connectWithQR() }
            } label: {
                Label("Add Another Wallet", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add another wallet")
            .accessibilityHint("Starts a new WalletConnect pairing without removing existing wallets.")
            .accessibilityIdentifier(A11yID.AuraPlay.walletPickerConnect)
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraSectionHeader(title: "Connect", subtitle: "Use an installed wallet app or the generic QR pairing.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(service.providers) { provider in
                    Button {
                        Task { await service.connect(with: provider) }
                    } label: {
                        Label(provider.displayName, systemImage: provider.systemImageName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Connect with \(provider.displayName)")
                    .accessibilityHint("Starts WalletConnect pairing for \(provider.displayName).")
                    .accessibilityIdentifier(A11yID.AuraPlay.walletPickerProvider(id: provider.id.rawValue))
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.walletPickerProviderList)
        }
    }

    private func pairingPayloadView(_ payload: String) -> some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                AuraSectionHeader(title: "Pairing Code", subtitle: "Scan or copy this from a WalletConnect v2 compatible wallet.")

                WalletQRCodeView(payload: payload)
                    .frame(width: 176, height: 176)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("WalletConnect QR code")
                    .accessibilityHint("Scan this code from another wallet app to approve the connection.")

                Text(payload)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.walletPickerQR)
    }

    private func errorView(_ message: String) -> some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 16) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(A11yID.AuraPlay.walletPickerError)
    }

    private var connectionOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(connectionOverlayTitle)
                .font(.headline)
            Button("Cancel") {
                service.cancel()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(A11yID.AuraPlay.walletPickerCancel)
        }
        .padding(24)
        .frame(maxWidth: 280)
        .auraSurfaceBackground(style: .regular, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    private var connectionOverlayTitle: String {
        switch service.phase {
        case .connecting(let provider):
            "Opening \(provider)..."
        case .awaitingApproval:
            "Waiting for wallet approval..."
        default:
            "Connecting..."
        }
    }

    private var isConnecting: Bool {
        switch service.phase {
        case .connecting, .awaitingApproval:
            true
        default:
            false
        }
    }
}

private struct WalletPickerAccountRow: View {
    let account: EOAccount
    let isActive: Bool
    let isSigningIn: Bool
    let select: () -> Void
    let remove: () -> Void
    let signIn: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            WalletBlockie(address: account.address)
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.walletDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(account.currentChain.routingDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSigningIn {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Signing in")
            } else if isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel("Active wallet")
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .auraSurfaceBackground(style: isActive ? .regular : .soft, cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .contextMenu {
            if let signIn {
                Button(action: signIn) {
                    Label("Sign-In with Ethereum", systemImage: "signature")
                }
            }
            Button(role: .destructive, action: remove) {
                Label("Remove Wallet", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.walletDisplayName), \(account.currentChain.routingDisplayName)")
        .accessibilityValue(isActive ? "Active wallet" : "Inactive wallet")
        .accessibilityHint("Double tap to use this wallet for AuraPlay discovery. Use actions to sign in or remove it.")
        .accessibilityIdentifier(A11yID.AuraPlay.walletPickerRow(address: account.address))
        .accessibilityAction(named: "Remove Wallet", remove)
        .accessibilityAction(named: "Sign-In with Ethereum") { signIn?() }
    }
}

private struct WalletQRCodeView: View {
    let payload: String

    var body: some View {
        if let image = Self.makeImage(payload: payload) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ContentUnavailableView("QR unavailable", systemImage: "qrcode")
        }
    }

    private static func makeImage(payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let image = output.transformed(by: transform)
        return UIImage(ciImage: image)
    }
}

private struct WalletBlockie: View {
    let address: String

    var body: some View {
        Canvas { context, size in
            let colors = Self.colors(for: address)
            let cell = min(size.width, size.height) / 5
            for row in 0..<5 {
                for column in 0..<5 {
                    let mirroredColumn = column > 2 ? 4 - column : column
                    let index = row * 3 + mirroredColumn
                    guard index < colors.count, colors[index].isFilled else { continue }
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(colors[index].color))
                }
            }
        }
        .background(Color.secondary.opacity(0.12))
    }

    private static func colors(for address: String) -> [(isFilled: Bool, color: Color)] {
        let scalars = Array(address.lowercased().unicodeScalars.map(\.value))
        let seed = scalars.reduce(UInt32(5381)) { (($0 << 5) &+ $0) &+ $1 }
        let hue = Double(seed % 360) / 360.0
        return (0..<15).map { index in
            let value = (seed >> UInt32(index % 16)) & 1
            let brightness = 0.45 + (Double((seed >> UInt32((index + 4) % 16)) & 3) * 0.1)
            return (value == 1, Color(hue: hue, saturation: 0.65, brightness: brightness))
        }
    }
}

private extension EOAccount {
    var walletDisplayName: String {
        if let name, !name.isEmpty {
            name
        } else {
            address.truncatedWalletAddress
        }
    }
}

private extension String {
    var truncatedWalletAddress: String {
        guard count > 12 else { return self }
        return "\(prefix(6))...\(suffix(4))"
    }
}

private extension ThirdPartyWalletProvider {
    var systemImageName: String {
        switch id.rawValue {
        case "generic-wallet":
            "qrcode"
        case "phantom", "backpack", "solflare":
            "sparkle"
        default:
            "wallet.pass"
        }
    }
}

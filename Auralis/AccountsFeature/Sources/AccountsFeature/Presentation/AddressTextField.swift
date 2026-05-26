import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import CodeScanner
import OSLog
import SwiftUI
import UIKit


public struct AddressTextField: View {
    @Binding private var address: String
    @FocusState private var isFocused: Bool

    public init(address: Binding<String>) {
        self._address = address
    }

    public var body: some View {
        HStack(spacing: 12) {
            TextField(
                "Ethereum Address",
                text: $address,
                prompt: Text("0x... wallet address").foregroundStyle(Color.textSecondary)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.alphabet)
            .textContentType(.URL)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .focused($isFocused)

            Divider()
                .frame(height: 20)
                .overlay(Color.textSecondary.opacity(0.2))

            Button("Paste", action: pasteAddress)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.textSecondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func pasteAddress() {
        guard let value = AddressPasteboardValue(rawValue: UIPasteboard.general.string) else {
            return
        }

        address = value.address
        isFocused = true
    }
}


@MainActor
public protocol AccountActivating {
    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        correlationID: String?
    ) async throws -> AccountActivationResult
}

public struct AccountENSResolution: Equatable, Sendable {
    public let address: String
    public let ensName: String
    public let isStale: Bool

    public init(address: String, ensName: String, isStale: Bool) {
        self.address = address
        self.ensName = ensName
        self.isStale = isStale
    }
}

public enum AccountENSResolutionFailure: LocalizedError, Equatable, Sendable {
    case mappingChanged(ensName: String, cachedAddress: String, resolvedAddress: String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .mappingChanged:
            return "The ENS mapping changed."
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
public protocol AccountENSResolving {
    func resolveAddress(forENS ensName: String, correlationID: String) async throws -> AccountENSResolution
}

@MainActor
public protocol AccountSwitching {
    func persistPreferredChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount

    func persistCurrentChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount
}

@MainActor
public struct AccountsGatewayDependencies {
    public let ensResolver: any AccountENSResolving
    public let accountActivator: any AccountActivating

    public init(
        ensResolver: any AccountENSResolving,
        accountActivator: any AccountActivating
    ) {
        self.ensResolver = ensResolver
        self.accountActivator = accountActivator
    }
}


public struct GatewayBackgroundImage: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [Color.deepBlue, Color.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image("aurora-1")
                .resizable()
                .aspectRatio(contentMode: .fill)
        )
    }
}


public struct AccountsGatewayView: View {
    private let dependencies: AccountsGatewayDependencies
    private let onAccountActivated: @MainActor (EOAccount, String?) -> Void

    public init(
        dependencies: AccountsGatewayDependencies,
        onAccountActivated: @escaping @MainActor (EOAccount, String?) -> Void
    ) {
        self.dependencies = dependencies
        self.onAccountActivated = onAccountActivated
    }

    public var body: some View {
        AccountsScenicScreen(contentAlignment: .center) {
            AddressInputView(
                dependencies: dependencies,
                onAccountActivated: onAccountActivated
            )
        }
    }
}

#Preview("Gateway Large Text") {
    AccountsGatewayView(
        dependencies: .preview,
        onAccountActivated: { _, _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Gateway Dark Mode") {
    AccountsGatewayView(
        dependencies: .preview,
        onAccountActivated: { _, _ in }
    )
    .preferredColorScheme(.dark)
}

private extension AccountsGatewayDependencies {
    static var preview: AccountsGatewayDependencies {
        AccountsGatewayDependencies(
            ensResolver: PreviewAccountENSResolver(),
            accountActivator: PreviewAccountActivator()
        )
    }
}

@MainActor
private struct PreviewAccountENSResolver: AccountENSResolving {
    func resolveAddress(forENS ensName: String, correlationID: String) async throws -> AccountENSResolution {
        AccountENSResolution(
            address: "0x0000000000000000000000000000000000000000",
            ensName: ensName,
            isStale: false
        )
    }
}

@MainActor
private struct PreviewAccountActivator: AccountActivating {
    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        correlationID: String?
    ) async throws -> AccountActivationResult {
        AccountActivationResult(
            account: EOAccount(
                address: rawAddress.isEmpty ? "0x0000000000000000000000000000000000000000" : rawAddress,
                name: name,
                source: source,
                lastSelectedAt: .now
            ),
            wasCreated: true
        )
    }
}

private struct AccountsScenicScreen<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let contentAlignment: Alignment
    private let content: () -> Content

    init(
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        contentAlignment: Alignment = .top,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.contentAlignment = contentAlignment
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
            .safeAreaPadding(.horizontal, horizontalPadding)
            .safeAreaPadding(.vertical, verticalPadding)
            .background {
                GatewayBackgroundImage()
                    .ignoresSafeArea()

                Color.background.opacity(0.3)
                    .ignoresSafeArea()
            }
    }
}


public struct AddressInputView: View {
    private struct PendingENSMappingChange: Identifiable, Equatable {
        let id = UUID()
        let ensName: String
        let cachedAddress: String
        let resolvedAddress: String
        let source: EOAccountSource
        let correlationID: String
    }

    @State private var address = ""
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingENSMappingChangeAlert = false
    @State private var isSubmitting = false
    @State private var activeSubmissionTask: Task<Void, Never>?
    @State private var activeSubmissionID = UUID()
    @State private var pendingENSMappingChange: PendingENSMappingChange?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private let dependencies: AccountsGatewayDependencies
    private let onAccountActivated: @MainActor (EOAccount, String?) -> Void
    private let activationErrorPresenter = AccountActivationErrorPresenter()
    private let ensResolutionPresenter = AccountENSResolutionPresenter()

    public init(
        dependencies: AccountsGatewayDependencies,
        onAccountActivated: @escaping @MainActor (EOAccount, String?) -> Void
    ) {
        self.dependencies = dependencies
        self.onAccountActivated = onAccountActivated
    }

    private var validationPresentation: AddressEntryValidationPresentation {
        AddressEntryValidationPresentation.make(input: address)
    }

    private var isENSInput: Bool {
        AccountStore.looksLikeENSName(address)
    }

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    public var body: some View {
        AddressEntryContentView(
            address: $address,
            validationMessage: validationPresentation.validationMessage,
            normalizedAddress: validationPresentation.normalizedAddress,
            isSubmitting: isSubmitting,
            handleSubmit: handleSubmit,
            selectGuestPass: selectGuestPass,
            accountActivator: dependencies.accountActivator,
            onAccountActivated: onAccountActivated
        )
        .background(Color.surface.opacity(0.08))
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
                Text("Untrusted ENS mapping: \(change.ensName) moved from \(change.cachedAddress) to \(change.resolvedAddress). Save the updated address?")
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

    private func selectGuestPass(address: String) {
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
        let input = address
        let ensResolver = dependencies.ensResolver
        activeSubmissionTask = Task {
            await submit(
                input: input,
                source: source,
                submissionID: submissionID,
                ensResolver: ensResolver
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
        AuraAccessibilityAnnouncer.announce(message)
        haptics.notification(feedback)
    }

    @MainActor
    private func submit(
        input: String,
        source: EOAccountSource,
        submissionID: UUID,
        ensResolver: any AccountENSResolving
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

        let correlationID = UUID().uuidString

        do {
            isSubmitting = true
            AuraAccessibilityAnnouncer.announce("Resolving account")
            let activation: AccountActivationResult

            if isENSInput {
                let resolution = try await ensResolver.resolveAddress(
                    forENS: input,
                    correlationID: correlationID
                )
                guard submissionID == activeSubmissionID else { return }
                let presentation = ensResolutionPresenter.presentation(for: resolution)
                guard let resolvedAddress = presentation.resolvedAddress,
                      let resolvedName = presentation.resolvedName
                else {
                    isSubmitting = false
                    activeSubmissionTask = nil
                    let alert = presentation.alert ?? AccountErrorPresentation(
                        title: "ENS Verification Unavailable",
                        message: "Auralis could not verify that ENS name right now."
                    )
                    showAlert(
                        title: alert.title,
                        message: alert.message
                    )
                    return
                }
                activation = try await dependencies.accountActivator.activateWatchAccount(
                    from: resolvedAddress,
                    name: resolvedName,
                    source: source,
                    correlationID: correlationID
                )
            } else {
                guard submissionID == activeSubmissionID else { return }
                activation = try await dependencies.accountActivator.activateWatchAccount(
                    from: input,
                    name: nil,
                    source: source,
                    correlationID: correlationID
                )
            }

            guard submissionID == activeSubmissionID else { return }
            address = ""
            onAccountActivated(activation.account, correlationID)
            haptics.notification(.success)
            isSubmitting = false
            activeSubmissionTask = nil

            if !activation.wasCreated {
                showAlert(
                    title: "Account Already Added",
                    message: "Switched to the existing saved account for that address.",
                    feedback: .success
                )
            }
        } catch let error as AccountENSResolutionFailure {
            guard submissionID == activeSubmissionID else { return }
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
            case .unavailable:
                isSubmitting = false
                let presentation = ensResolutionPresenter.presentation(for: error)
                showAlert(
                    title: presentation.title,
                    message: presentation.message
                )
            }
        } catch is CancellationError {
            if submissionID == activeSubmissionID {
                isSubmitting = false
                activeSubmissionTask = nil
            }
        } catch {
            guard submissionID == activeSubmissionID else { return }
            activeSubmissionTask = nil
            isSubmitting = false
            let presentation = activationErrorPresenter.presentation(for: error)
            showAlert(
                title: presentation.title,
                message: presentation.message
            )
        }
    }

    @MainActor
    private func confirmENSMappingChange(_ change: PendingENSMappingChange) {
        Task {
            do {
                let activation = try await dependencies.accountActivator.activateWatchAccount(
                    from: change.resolvedAddress,
                    name: change.ensName,
                    source: change.source,
                    correlationID: change.correlationID
                )
                address = ""
                onAccountActivated(activation.account, change.correlationID)
                isSubmitting = false
                activeSubmissionTask = nil
                pendingENSMappingChange = nil

                if !activation.wasCreated {
                    showAlert(
                        title: "Account Already Added",
                        message: "Switched to the existing saved account for that address.",
                        feedback: .success
                    )
                }
            } catch {
                isSubmitting = false
                pendingENSMappingChange = nil
                let presentation = activationErrorPresenter.presentation(for: error)
                showAlert(
                    title: presentation.title,
                    message: presentation.message
                )
            }
        }
    }
}

private struct AddressEntryContentView: View {
    @Binding var address: String
    let validationMessage: String?
    let normalizedAddress: String?
    let isSubmitting: Bool
    let handleSubmit: () -> Void
    let selectGuestPass: (String) -> Void
    let accountActivator: any AccountActivating
    let onAccountActivated: @MainActor (EOAccount, String?) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .center) {
            AddressEntryHeaderView()

            inputRow
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

            AuraActionButton("Enter Auralis", style: .hero, action: handleSubmit)
                .disabled(isSubmitting)
                .padding(.horizontal, 30)

            if isSubmitting {
                ProgressView("Resolving account...")
                    .tint(Color.textPrimary)
                    .padding(.top, 8)
            }

            GuestExploreDividerView()
            GuestPassesHeaderView()
            GuestPassCarousel(items: GuestPassAccount.accounts) { account in
                selectGuestPass(account.address)
            }
        }
    }

    @ViewBuilder
    private var inputRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                QRScannerView(
                    accountActivator: accountActivator,
                    onAccountActivated: onAccountActivated
                )
                .transition(.opacity)

                AddressTextField(address: $address)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    QRScannerView(
                        accountActivator: accountActivator,
                        onAccountActivated: onAccountActivated
                    )
                    .transition(.opacity)

                    AddressTextField(address: $address)
                }

                VStack(alignment: .leading, spacing: 12) {
                    QRScannerView(
                        accountActivator: accountActivator,
                        onAccountActivated: onAccountActivated
                    )
                    .transition(.opacity)

                    AddressTextField(address: $address)
                }
            }
        }
    }
}

public struct AddressEntryHeaderView: View {
    public init() {}

    public var body: some View {
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

public struct GuestExploreDividerView: View {
    public init() {}

    public var body: some View {
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

public struct GuestPassesHeaderView: View {
    public init() {}

    public var body: some View {
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


@MainActor
public enum QRScanValidationOutcome: Equatable {
    case valid
    case alert(title: String, message: String)

    public static func classify(_ scannedValue: String) -> QRScanValidationOutcome {
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

public struct QRScannerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isScanning = false
    @State private var torchOn = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private let accountActivator: any AccountActivating
    private let onAccountActivated: @MainActor (EOAccount, String?) -> Void
    private let activationErrorPresenter = AccountActivationErrorPresenter()

    public init(
        accountActivator: any AccountActivating,
        onAccountActivated: @escaping @MainActor (EOAccount, String?) -> Void
    ) {
        self.accountActivator = accountActivator
        self.onAccountActivated = onAccountActivated
    }

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    public var body: some View {
        Button {
            isScanning = true
        } label: {
            SystemImage("qrcode.viewfinder")
                .foregroundStyle(Color.textPrimary.opacity(0.55))
                .font(.system(size: 30, weight: .medium))
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(String(localized: "Scan wallet QR code"))
        .accessibilityShowsLargeContentViewer()
        .sheet(isPresented: $isScanning) {
            ZStack(alignment: .top) {
                CodeScannerView(
                    codeTypes: [.qr],
                    requiresPhotoOutput: false,
                    isTorchOn: torchOn,
                    completion: handleScan
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    AuraTrustLabel(kind: .scan)
                    AccountTorchToggleButton(torchOn: $torchOn)
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
                let correlationID = UUID().uuidString
                do {
                    let activation = try await accountActivator.activateWatchAccount(
                        from: code.string,
                        name: nil,
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
                    let presentation = activationErrorPresenter.presentation(for: error)
                    showAlert(
                        title: presentation.title,
                        message: presentation.message
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
        AuraAccessibilityAnnouncer.announce(message)
        haptics.notification(feedback)
    }
}

private struct AccountTorchToggleButton: View {
    @Binding var torchOn: Bool

    var body: some View {
        Button {
            torchOn.toggle()
        } label: {
            HStack {
                SystemImage(torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .foregroundStyle(torchOn ? .accent : Color.secondary)
                PrimaryText(torchOn ? "Torch Off" : "Torch On")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(Color.surface.opacity(0.5))
        )
        .accessibilityLabel(String(localized: "Torch"))
        .accessibilityValue(torchOn ? "On" : "Off")
        .accessibilityHint(torchOn ? "Turns the torch off" : "Turns the torch on")
    }
}


public struct AccountSwitcherSelection: Equatable, Sendable {
    public let address: String
    public let chain: Chain

    public init(address: String, chain: Chain) {
        self.address = address
        self.chain = chain
    }
}

public struct AccountSwitcherSheet: View {
    private let logger = Logger(subsystem: "Auralis", category: "AccountSwitcherSheet")
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dismiss) private var dismiss

    private let persistedAccounts: [EOAccount]
    private let currentAccount: EOAccount?
    private let activeSelection: AccountSwitcherSelection?
    private let accountSwitcher: any AccountSwitching
    private let presenter = AccountSwitcherPresenter()
    private let onSelectAccount: @MainActor (String) -> Void
    private let onRemoveAccount: @MainActor (String) -> Void
    private let onCurrentChainChange: @MainActor (Chain, String) async throws -> Void

    @State private var pendingRemovalAccount: EOAccount?
    @State private var feedbackAlert: AccountSwitcherAlert?
    @State private var pendingPreferredChainSelections: [String: Chain] = [:]
    @State private var pendingCurrentChainSelections: [String: Chain] = [:]

    public init(
        persistedAccounts: [EOAccount],
        currentAccount: EOAccount?,
        activeSelection: AccountSwitcherSelection?,
        accountSwitcher: any AccountSwitching,
        onSelectAccount: @escaping @MainActor (String) -> Void,
        onRemoveAccount: @escaping @MainActor (String) -> Void,
        onCurrentChainChange: @escaping @MainActor (Chain, String) async throws -> Void
    ) {
        self.persistedAccounts = persistedAccounts
        self.currentAccount = currentAccount
        self.activeSelection = activeSelection
        self.accountSwitcher = accountSwitcher
        self.onSelectAccount = onSelectAccount
        self.onRemoveAccount = onRemoveAccount
        self.onCurrentChainChange = onCurrentChainChange
    }

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    private var presentedAccounts: [EOAccount] {
        presenter.sortedAccounts(persistedAccounts)
    }

    public var body: some View {
        NavigationStack {
            List {
                if persistedAccounts.isEmpty {
                    EmptyAccountsRow()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section("Saved Accounts") {
                        ForEach(presentedAccounts) { account in
                            AccountRow(
                                account: account,
                                isActive: activeSelection?.address == account.address,
                                onSelect: { select(account) },
                                onRemove: { pendingRemovalAccount = account }
                            )
                        }
                    }

                    if let selected = currentAccount {
                        chainScopeSection(for: selected)
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Remove Account",
                isPresented: Binding(
                    get: { pendingRemovalAccount != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingRemovalAccount = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let account = pendingRemovalAccount {
                    Button("Remove Account", role: .destructive) {
                        remove(account)
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingRemovalAccount = nil
                }
            } message: {
                if let account = pendingRemovalAccount {
                    Text("Remove \(account.address.accountFeatureDisplayAddress) from this device?")
                }
            }
            .alert(
                feedbackAlert?.title ?? "",
                isPresented: Binding(
                    get: { feedbackAlert != nil },
                    set: { isPresented in
                        if !isPresented {
                            feedbackAlert = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    feedbackAlert = nil
                }
            } message: {
                if let message = feedbackAlert?.message {
                    Text(message)
                }
            }
        }
    }

    private func select(_ account: EOAccount) {
        haptics.impact(.light)
        onSelectAccount(account.address)
        dismiss()
    }

    private func remove(_ account: EOAccount) {
        pendingRemovalAccount = nil
        haptics.notification(.warning)
        onRemoveAccount(account.address)

        if activeSelection?.address == account.address {
            dismiss()
        } else {
            feedbackAlert = AccountSwitcherAlert(
                title: "Account Removed",
                message: "\(account.address.accountFeatureDisplayAddress) was removed from this device."
            )
        }
    }

    private func applyChainScopeChange(_ plan: ChainScopeChangePlan, to account: EOAccount) {
        guard plan.shouldApply, let event = plan.event else {
            return
        }

        let correlationID = UUID().uuidString
        setPendingSelection(plan.to, kind: plan.kind, address: account.address)

        Task {
            do {
                switch plan.kind {
                case .preferred:
                    _ = try await accountSwitcher.persistPreferredChain(
                        address: account.address,
                        chain: plan.to,
                        correlationID: correlationID
                    )
                case .current:
                    break
                }

                if plan.shouldRefreshActiveScope {
                    try await onCurrentChainChange(plan.to, correlationID)
                }

                clearPendingSelection(kind: plan.kind, address: account.address)
                haptics.selection()
            } catch {
                clearPendingSelection(kind: plan.kind, address: account.address)
                haptics.notification(.error)

                logger.error("Failed to persist chain scope change address=\(account.address, privacy: .private(mask: .hash)) kind=\(String(describing: plan.kind), privacy: .public) event=\(String(describing: event), privacy: .public) to=\(plan.to.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                feedbackAlert = AccountSwitcherAlert(
                    title: "Chain Change Failed",
                    message: "Auralis could not save that chain change. Your previous chain settings are still active."
                )
            }
        }
    }

    @ViewBuilder
    private func chainScopeSection(for account: EOAccount) -> some View {
        Section("Chain Scope") {
            ChainPickerRow(
                title: "Preferred Chain",
                selection: preferredChainBinding(for: account)
            )

            ChainPickerRow(
                title: "Current Chain",
                selection: currentChainBinding(for: account)
            )
        }
    }

    private func preferredChainBinding(for account: EOAccount) -> Binding<Chain> {
        Binding(
            get: { pendingPreferredChainSelections[account.address] ?? account.preferredChain },
            set: { newValue in
                applyChainScopeChange(
                    ChainScopeChangePlanner().planPreferredChange(
                        address: account.address,
                        from: pendingPreferredChainSelections[account.address] ?? account.preferredChain,
                        to: newValue
                    ),
                    to: account
                )
            }
        )
    }

    private func currentChainBinding(for account: EOAccount) -> Binding<Chain> {
        Binding(
            get: { currentChainSelection(for: account) },
            set: { newValue in
                applyChainScopeChange(
                    ChainScopeChangePlanner().planCurrentChange(
                        address: account.address,
                        from: currentChainSelection(for: account),
                        to: newValue
                    ),
                    to: account
                )
            }
        )
    }

    private func currentChainSelection(for account: EOAccount) -> Chain {
        if let pendingSelection = pendingCurrentChainSelections[account.address] {
            return pendingSelection
        }

        if activeSelection?.address == account.address {
            return activeSelection?.chain ?? account.currentChain
        }

        return account.currentChain
    }

    private func setPendingSelection(_ chain: Chain, kind: ChainScopeChangeKind, address: String) {
        switch kind {
        case .preferred:
            pendingPreferredChainSelections[address] = chain
        case .current:
            pendingCurrentChainSelections[address] = chain
        }
    }

    private func clearPendingSelection(kind: ChainScopeChangeKind, address: String) {
        switch kind {
        case .preferred:
            pendingPreferredChainSelections.removeValue(forKey: address)
        case .current:
            pendingCurrentChainSelections.removeValue(forKey: address)
        }
    }
}

private struct EmptyAccountsRow: View {
    var body: some View {
        VStack(spacing: 12) {
            SystemImage("person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("No Saved Accounts")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text("Add or scan a wallet address to build your local roster. Guest passes stay in demo territory until you decide to save an account on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountRow: View {
    let account: EOAccount
    let isActive: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    if let name = account.name {
                        Text(name)
                            .foregroundStyle(Color.textSecondary)
                            .fontWeight(.semibold)

                        Text(account.address.accountFeatureDisplayAddress)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text(account.address.accountFeatureDisplayAddress)
                            .foregroundStyle(Color.textSecondary)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(account.name ?? account.address.accountFeatureDisplayAddress)
            .accessibilityValue(isActive ? "Active account" : "Inactive account")
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityIdentifier("accounts.select.\(account.address)")

            if isActive {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accent.opacity(0.18))
                    )
                    .foregroundStyle(Color.accent)
                    .accessibilityHidden(true)
            }

            Button(role: .destructive, action: onRemove) {
                SystemImage("trash")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "Remove account \(account.address.accountFeatureDisplayAddress)"))
            .accessibilityIdentifier("accounts.remove.\(account.address)")
        }
        .padding(.vertical, 4)
    }
}

private struct AccountSwitcherAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

public enum ChainScopeChangeKind: Equatable, Sendable {
    case preferred
    case current
}

public struct ChainScopeChangePlan: Equatable {
    public let kind: ChainScopeChangeKind
    public let to: Chain
    public let shouldApply: Bool
    public let shouldRefreshActiveScope: Bool
    public let event: AccountEvent?

    public init(
        kind: ChainScopeChangeKind,
        to: Chain,
        shouldApply: Bool,
        shouldRefreshActiveScope: Bool,
        event: AccountEvent?
    ) {
        self.kind = kind
        self.to = to
        self.shouldApply = shouldApply
        self.shouldRefreshActiveScope = shouldRefreshActiveScope
        self.event = event
    }
}

public struct ChainScopeChangePlanner: Sendable {
    public init() {}

    public func planPreferredChange(address: String, from: Chain, to: Chain) -> ChainScopeChangePlan {
        makePlan(kind: .preferred, address: address, from: from, to: to)
    }

    public func planCurrentChange(address: String, from: Chain, to: Chain) -> ChainScopeChangePlan {
        makePlan(kind: .current, address: address, from: from, to: to)
    }

    private func makePlan(
        kind: ChainScopeChangeKind,
        address: String,
        from: Chain,
        to: Chain
    ) -> ChainScopeChangePlan {
        guard from != to else {
            return ChainScopeChangePlan(
                kind: kind,
                to: to,
                shouldApply: false,
                shouldRefreshActiveScope: false,
                event: nil
            )
        }

        let event: AccountEvent = switch kind {
        case .preferred:
            .preferredChainChanged(address: address, from: from, to: to)
        case .current:
            .currentChainChanged(address: address, from: from, to: to)
        }

        return ChainScopeChangePlan(
            kind: kind,
            to: to,
            shouldApply: true,
            shouldRefreshActiveScope: kind == .current,
            event: event
        )
    }
}

private struct ChainPickerRow: View {
    let title: String
    @Binding var selection: Chain

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: $selection) {
                Text("Ethereum").tag(Chain.ethMainnet)
                Text("Polygon").tag(Chain.polygonMainnet)
                Text("Arbitrum").tag(Chain.arbMainnet)
                Text("Optimism").tag(Chain.optMainnet)
                Text("Base").tag(Chain.baseMainnet)
            }
            .pickerStyle(.menu)
        }
    }
}

private extension String {
    var accountFeatureDisplayAddress: String {
        guard count > 10 else {
            return self
        }

        return "\(prefix(6))...\(suffix(4))"
    }
}

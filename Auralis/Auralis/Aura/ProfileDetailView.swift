import SwiftData
import SwiftUI

struct ProfileDetailPresentation: Equatable {
    let title: String
    let addressLine: String
    let chainTitle: String
    let sourceTitle: String
    let scopedNFTLabel: String
    let scopedTokenLabel: String
    let activityLabel: String
    let isCurrentAccount: Bool
}

struct ProfileDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]
    @Query private var nfts: [NFT]
    @Query private var holdings: [TokenHolding]

    let accountAddress: String
    let currentChain: Chain
    let isCurrentAccount: Bool
    let showsPolicySection: Bool
    let modeState: ModeState?
    let services: ShellServiceHub?
    let onOpenSettings: (() -> Void)?

    @State private var denialMessage: String?

    init(
        accountAddress: String,
        currentChain: Chain,
        isCurrentAccount: Bool = false,
        showsPolicySection: Bool = false,
        modeState: ModeState? = nil,
        services: ShellServiceHub? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.accountAddress = accountAddress
        self.currentChain = currentChain
        self.isCurrentAccount = isCurrentAccount
        self.showsPolicySection = showsPolicySection
        self.modeState = modeState
        self.services = services
        self.onOpenSettings = onOpenSettings

        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        _accounts = Query(
            filter: #Predicate<EOAccount> {
                $0.address == normalizedAccountAddress
            }
        )
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress
            }
        )
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress
            }
        )
    }

    private let blockedActions: [PolicyControlledAction] = [
        .signMessage,
        .approveSpending,
        .draftTransaction
    ]

    private var account: EOAccount? {
        accounts.first
    }

    private var scopedNFTCount: Int {
        nfts.filter { $0.networkRawValue == currentChain.rawValue }.count
    }

    private var scopedTokenCount: Int {
        holdings.filter { $0.chainRawValue == currentChain.rawValue }.count
    }

    private var presentation: ProfileDetailPresentation {
        Self.makePresentation(
            account: account,
            accountAddress: accountAddress,
            currentChain: currentChain,
            scopedNFTCount: scopedNFTCount,
            scopedTokenCount: scopedTokenCount,
            isCurrentAccount: isCurrentAccount
        )
    }

    var body: some View {
        AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(presentation.title)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)

                                    Text(presentation.addressLine)
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(Color.textSecondary)

                                    Text(presentation.chainTitle)
                                        .font(.footnote)
                                        .foregroundStyle(Color.textSecondary)
                                }

                                Spacer(minLength: 12)

                                if presentation.isCurrentAccount {
                                    AuraPill(
                                        "Current",
                                        systemImage: "person.crop.circle.fill",
                                        emphasis: .accent
                                    )
                                }
                            }

                            HStack(spacing: 8) {
                                AuraPill(
                                    presentation.sourceTitle,
                                    systemImage: "person.text.rectangle",
                                    emphasis: .neutral
                                )
                                AuraPill(
                                    presentation.scopedNFTLabel,
                                    systemImage: "square.stack",
                                    emphasis: .neutral
                                )
                                AuraPill(
                                    presentation.scopedTokenLabel,
                                    systemImage: "dollarsign.circle",
                                    emphasis: .neutral
                                )
                            }

                            Text(presentation.activityLabel)
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if showsPolicySection {
                        observeModeSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let onOpenSettings {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .alert("Not available in Observe mode", isPresented: denialAlertBinding) {
            Button("OK", role: .cancel) {
                denialMessage = nil
            }
        } message: {
            Text(denialMessage ?? "This action is not available right now.")
        }
    }

    @ViewBuilder
    private var observeModeSection: some View {
        ShellStatusCard(
            eyebrow: "Observe Mode",
            title: "Execution Is Locked",
            message: "Auralis is currently read-only. Signing, approvals, and transaction drafting stay blocked until a later phase unlocks them intentionally.",
            systemImage: "eye.slash",
            tone: .warning
        )

        ForEach(blockedActions, id: \.rawValue) { action in
            AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text(action.summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 8)

                    AuraActionButton("Try", style: .surface) {
                        attempt(action)
                    }
                }
            }
        }
    }

    private var denialAlertBinding: Binding<Bool> {
        Binding(
            get: { denialMessage != nil },
            set: { isPresented in
                if !isPresented {
                    denialMessage = nil
                }
            }
        )
    }

    private func attempt(_ action: PolicyControlledAction) {
        guard let services, let modeState else {
            return
        }

        let result = services.policyActionHandlerFactory(modelContext, modeState).attempt(action)
        if !result.isAllowed {
            denialMessage = result.userMessage
        }
    }

    static func makePresentation(
        account: EOAccount?,
        accountAddress: String,
        currentChain: Chain,
        scopedNFTCount: Int,
        scopedTokenCount: Int,
        isCurrentAccount: Bool
    ) -> ProfileDetailPresentation {
        let resolvedTitle = account?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTitle = account?.source.profileTitle ?? "Imported"
        let activityDate = account?.mostRecentActivityAt ?? account?.addedAt ?? .now

        return ProfileDetailPresentation(
            title: (resolvedTitle?.isEmpty == false ? resolvedTitle! : EOAccount.defaultName(for: accountAddress)),
            addressLine: accountAddress.displayAddress,
            chainTitle: "\(currentChain.routingDisplayName) scope",
            sourceTitle: sourceTitle,
            scopedNFTLabel: scopedNFTCount == 1 ? "1 NFT" : "\(scopedNFTCount) NFTs",
            scopedTokenLabel: scopedTokenCount == 1 ? "1 token" : "\(scopedTokenCount) tokens",
            activityLabel: "Last active \(activityDate.formatted(date: .abbreviated, time: .omitted))",
            isCurrentAccount: isCurrentAccount
        )
    }
}

private extension EOAccountSource {
    var profileTitle: String {
        switch self {
        case .manualEntry:
            return "Manual"
        case .qrScan:
            return "QR"
        case .guestPass:
            return "Guest Pass"
        }
    }
}

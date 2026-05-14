import AccountsCore
import AuralisPrimaryModels
import AuralisShellCore
import OSLog
import SwiftData
import SwiftUI
import AuraUI
import UIKit

struct AccountSwitcherSheet: View {
    private let logger = Logger(subsystem: "Auralis", category: "AccountSwitcherSheet")
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
            SortDescriptor(\EOAccount.addedAt, order: .reverse),
            SortDescriptor(\EOAccount.address)
        ]
    ) private var persistedAccounts: [EOAccount]

    let currentAccount: EOAccount?
    let activeSelection: ActiveShellSelection?
    let accountStoreFactory: @MainActor (ModelContext) -> any AccountStoring
    let onSelectAccount: @MainActor (String) -> Void
    let onRemoveAccount: @MainActor (String) -> Void
    let onCurrentChainChange: @MainActor (Chain) -> Void

    @State private var pendingRemovalAccount: EOAccount?
    @State private var feedbackAlert: AccountSwitcherAlert?
    @State private var pendingPreferredChainSelections: [String: Chain] = [:]
    @State private var pendingCurrentChainSelections: [String: Chain] = [:]

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    var body: some View {
        NavigationStack {
            List {
                if persistedAccounts.isEmpty {
                    ShellStatusCard(
                        eyebrow: "First Run",
                        title: "No Saved Accounts",
                        message: "Add or scan a wallet address to build your local roster. Guest passes stay in demo territory until you decide to save an account on this device.",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        tone: .neutral
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section("Saved Accounts") {
                        ForEach(persistedAccounts) { account in
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
                    Text("Remove \(account.address.displayAddress) from this device?")
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
                message: "\(account.address.displayAddress) was removed from this device."
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
                let store = accountStoreFactory(modelContext)
                switch plan.kind {
                case .preferred:
                    _ = try await store.persistPreferredChain(
                        address: account.address,
                        chain: plan.to,
                        correlationID: correlationID
                    )
                case .current:
                    _ = try await store.persistCurrentChain(
                        address: account.address,
                        chain: plan.to,
                        correlationID: correlationID
                    )
                }

                clearPendingSelection(kind: plan.kind, address: account.address)
                haptics.selection()

                if plan.shouldRefreshActiveScope {
                    onCurrentChainChange(plan.to)
                }
            } catch {
                clearPendingSelection(kind: plan.kind, address: account.address)
                haptics.notification(.error)

                logger.error(
                    "Failed to persist chain scope change address=\(account.address, privacy: .private(mask: .hash)) kind=\(String(describing: plan.kind), privacy: .public) event=\(String(describing: event), privacy: .public) to=\(plan.to.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
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
            get: {
                if let pendingSelection = pendingCurrentChainSelections[account.address] {
                    return pendingSelection
                }

                if activeSelection?.address == account.address {
                    return activeSelection?.chain ?? account.currentChain
                }

                return account.currentChain
            },
            set: { newValue in
                applyChainScopeChange(
                    ChainScopeChangePlanner().planCurrentChange(
                        address: account.address,
                        from: pendingCurrentChainSelections[account.address] ?? account.currentChain,
                        to: newValue
                    ),
                    to: account
                )
            }
        )
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

                        Text(account.address.displayAddress)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text(account.address.displayAddress)
                            .foregroundStyle(Color.textSecondary)
                            .fontWeight(.semibold)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
            }

            Button(role: .destructive, action: onRemove) {
                SystemImage("trash")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove account")
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

enum ChainScopeChangeKind: Equatable {
    case preferred
    case current
}

struct ChainScopeChangePlan: Equatable {
    let kind: ChainScopeChangeKind
    let to: Chain
    let shouldApply: Bool
    let shouldRefreshActiveScope: Bool
    let event: AccountEvent?
}

struct ChainScopeChangePlanner {
    func planPreferredChange(address: String, from: Chain, to: Chain) -> ChainScopeChangePlan {
        makePlan(
            kind: .preferred,
            address: address,
            from: from,
            to: to
        )
    }

    func planCurrentChange(address: String, from: Chain, to: Chain) -> ChainScopeChangePlan {
        makePlan(
            kind: .current,
            address: address,
            from: from,
            to: to
        )
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

import SwiftData
import SwiftUI

struct AccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var persistedAccounts: [EOAccount]

    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChain: Chain
    let onAccountSelectionStarted: @MainActor (String) -> Void
    let onCurrentChainChanged: @MainActor (Chain, String) -> Void

    @State private var pendingRemovalAccount: EOAccount?
    @State private var feedbackAlert: AccountSwitcherAlert?

    private var orderedAccounts: [EOAccount] {
        persistedAccounts.sorted { lhs, rhs in
            if lhs.mostRecentActivityAt != rhs.mostRecentActivityAt {
                return lhs.mostRecentActivityAt > rhs.mostRecentActivityAt
            }

            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt > rhs.addedAt
            }

            return lhs.address.localizedCompare(rhs.address) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if orderedAccounts.isEmpty {
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
                        ForEach(orderedAccounts) { account in
                            AccountRow(
                                account: account,
                                isActive: currentAddress == account.address,
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
        let store = AccountStore(
            modelContext: modelContext,
            eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
        )

        do {
            let correlationID = UUID().uuidString
            onAccountSelectionStarted(correlationID)
            let selectedAccount = try store.selectAccount(
                address: account.address,
                correlationID: correlationID
            )
            currentAccount = selectedAccount
            currentAddress = selectedAccount.address
            dismiss()
        } catch {
            feedbackAlert = AccountSwitcherAlert(
                title: "Selection Failed",
                message: error.localizedDescription
            )
        }
    }

    private func remove(_ account: EOAccount) {
        pendingRemovalAccount = nil
        let store = AccountStore(
            modelContext: modelContext,
            eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
        )

        do {
            let correlationID = UUID().uuidString
            let result = try store.removeAccount(
                address: account.address,
                activeAddress: currentAddress,
                correlationID: correlationID
            )

            if currentAddress == result.removedAddress {
                if let fallbackAccount = result.fallbackAccount {
                    currentAccount = fallbackAccount
                    currentAddress = fallbackAccount.address
                    feedbackAlert = AccountSwitcherAlert(
                        title: "Active Account Removed",
                        message: "Switched to \(fallbackAccount.address.displayAddress). Pick another account if needed."
                    )
                } else {
                    currentAccount = nil
                    currentAddress = ""
                    dismiss()
                }
            } else {
                if currentAccount?.address == result.removedAddress {
                    currentAccount = nil
                }

                feedbackAlert = AccountSwitcherAlert(
                    title: "Account Removed",
                    message: "\(account.address.displayAddress) was removed from this device."
                )
            }
        } catch {
            feedbackAlert = AccountSwitcherAlert(
                title: "Removal Failed",
                message: error.localizedDescription
            )
        }
    }

    private func applyChainScopeChange(_ plan: ChainScopeChangePlan, to account: EOAccount) {
        guard plan.shouldApply, let event = plan.event else {
            return
        }

        let correlationID = UUID().uuidString

        switch plan.kind {
        case .preferred:
            account.preferredChain = plan.to
        case .current:
            account.currentChain = plan.to
            if currentAccount?.address == account.address {
                currentChain = plan.to
            }
        }

        try? modelContext.save()
        AccountEventRecorders.live(modelContext: modelContext).record(
            event,
            correlationID: correlationID
        )

        if plan.shouldRefreshActiveScope {
            onCurrentChainChanged(plan.to, correlationID)
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
            get: { account.preferredChain },
            set: { newValue in
                applyChainScopeChange(
                    ChainScopeChangePlanner().planPreferredChange(
                        address: account.address,
                        from: account.preferredChain,
                        to: newValue
                    ),
                    to: account
                )
            }
        )
    }

    private func currentChainBinding(for account: EOAccount) -> Binding<Chain> {
        Binding(
            get: { account.currentChain },
            set: { newValue in
                applyChainScopeChange(
                    ChainScopeChangePlanner().planCurrentChange(
                        address: account.address,
                        from: account.currentChain,
                        to: newValue
                    ),
                    to: account
                )
            }
        )
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

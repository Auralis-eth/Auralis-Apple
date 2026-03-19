import SwiftData
import SwiftUI

struct AccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var persistedAccounts: [EOAccount]

    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String

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
            let selectedAccount = try store.selectAccount(address: account.address)
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
            let result = try store.removeAccount(
                address: account.address,
                activeAddress: currentAddress
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
                    Text(account.name ?? account.address.displayAddress)
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.semibold)

                    Text(account.address.displayAddress)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
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
                Image(systemName: "trash")
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

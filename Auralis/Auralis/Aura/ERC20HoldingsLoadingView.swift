import SwiftUI

struct ERC20HoldingsLoadingView: View {
    let chain: Chain

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Syncing Token Holdings")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Text("Fetching \(chain.routingDisplayName) balances and metadata for the active wallet.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("erc20.loading")
    }
}

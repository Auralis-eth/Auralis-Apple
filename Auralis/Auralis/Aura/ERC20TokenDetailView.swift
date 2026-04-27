import SwiftData
import SwiftUI

struct ERC20TokenDetailView: View {
    let route: ERC20TokenRoute
    let currentAccountAddress: String

    @Query private var holdings: [TokenHolding]

    init(route: ERC20TokenRoute, currentAccountAddress: String) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let contractAddress = NFT.normalizedScopeComponent(route.contractAddress) ?? route.contractAddress
        let chainRawValue = route.chain.rawValue
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue &&
                $0.contractAddressRawValue == contractAddress
            }
        )
    }

    private var presentation: ERC20TokenDetailPresentation {
        ERC20TokenDetailPresentation(
            route: route,
            holding: holdings.first
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        AuraTrustLabel(kind: .provider)

                        Text(presentation.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .accessibilityIdentifier("erc20.detail.title")

                        if let symbol = presentation.symbol {
                            Text(symbol)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }

                        HStack(spacing: 10) {
                            BadgeLabel(title: presentation.chainTitle)

                            if presentation.isPlaceholder {
                                BadgeLabel(title: "Metadata pending")
                            }

                            if presentation.isAmountHidden {
                                BadgeLabel(title: "Amount hidden")
                            }

                            if presentation.isMetadataStale {
                                BadgeLabel(title: "Metadata stale")
                            }

                            if presentation.isNativeStyleFallback {
                                BadgeLabel(title: "Native-style fallback")
                            }
                        }

                        if let metadataStatus = presentation.metadataStatus {
                            SecondaryText(metadataStatus)
                        }
                    }
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HeadlineFontText("Balance")
                        ERC20TokenDetailRow(title: "Amount", value: presentation.amountDisplay)
                        ERC20TokenDetailRow(title: "Scope", value: presentation.scopeTitle)
                        ERC20TokenDetailRow(title: "Updated", value: presentation.updatedLabel)
                    }
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HeadlineFontText("Token Identity")
                        ERC20TokenDetailRow(title: "Name", value: presentation.title)
                        ERC20TokenDetailRow(title: "Symbol", value: presentation.symbol)
                        ERC20TokenDetailRow(title: "Contract", value: presentation.contractAddress)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("erc20.detail.screen")
    }
}

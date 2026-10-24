import SwiftData
import SwiftUI

/// Root of the dedicated "Social" tab (Social v1). Hosts the invite exchange for starting or joining a
/// shared session. Shown only when relay social is enabled; the tab is not added to the bar otherwise.
struct SocialTabView: View {
    private let composition: SocialInviteExchangeComposition
    @State private var sessionID = UUID()

    init(
        modelContext: ModelContext,
        modeState: ModeState,
        accountAddress: String?,
        chainID: Int?,
        auraPlayModelContainer: ModelContainer?,
        walletConnectionService: AuralisWalletConnectionService?
    ) {
        composition = SocialAssembly.makeInviteExchange(
            modelContext: modelContext,
            modeState: modeState,
            accountAddress: accountAddress,
            chainID: chainID,
            auraPlayModelContainer: auraPlayModelContainer,
            walletConnectionService: walletConnectionService
        )
    }

    var body: some View {
        NavigationStack {
            SocialInviteExchangeView(composition: composition, sessionID: sessionID)
        }
    }
}

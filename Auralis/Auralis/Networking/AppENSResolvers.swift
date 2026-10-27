import AuralisPrimaryModels
import ENS
import Foundation
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import AuralisReceipts
import SwiftData

@MainActor
extension ENSResolvers {
    static func live(
        modelContext: ModelContext,
        cacheStore: ENSResolutionCacheStore = sharedCacheStore,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { .observe }
    ) -> any ENSResolving {
        live(
            configurationResolver: ProviderBackedENSConfigurationResolver(
                configurationResolver: LiveProviderConfigurationResolver()
            ),
            cacheStore: cacheStore,
            eventRecorder: ReceiptBackedENSEventRecorder(
                receiptStore: ReceiptStores.live(modelContext: modelContext),
                modeProvider: modeProvider
            )
        )
    }
}

import ReceiptsCore
import ReceiptStorage
import ENS
import AuralisPrimaryModels
import Foundation
import ProviderKit
import SwiftData
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

@MainActor
extension ENSResolvers {
    static func live(
        modelContext: ModelContext,
        cacheStore: ENSResolutionCacheStore = sharedCacheStore
    ) -> any ENSResolving {
        live(
            configurationResolver: ProviderBackedENSConfigurationResolver(
                configurationResolver: LiveProviderConfigurationResolver()
            ),
            cacheStore: cacheStore,
            eventRecorder: ReceiptBackedENSEventRecorder(
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
        )
    }
}

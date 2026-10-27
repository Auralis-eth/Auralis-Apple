import AuralisCrypto
import Foundation
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

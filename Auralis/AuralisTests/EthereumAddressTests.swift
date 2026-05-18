import AccountsCore
import AuralisPrimaryModels
import Foundation
import Testing

@Suite
struct EthereumAddressTests {
    @Test("normalizes supported wallet address input to lowercase 0x form")
    func normalizesWalletAddressInput() {
        #expect(AuralisEthereumAddress.normalized("  0xABCDEF1234567890ABCDEF1234567890ABCDEF12  ") == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(AuralisEthereumAddress.normalized("ABCDEF1234567890ABCDEF1234567890ABCDEF12") == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(AuralisEthereumAddress(rawValue: "0XABCDEF1234567890ABCDEF1234567890ABCDEF12")?.rawValue == "0xabcdef1234567890abcdef1234567890abcdef12")
    }

    @Test("rejects non-address input without partial extraction")
    func rejectsInvalidWalletAddressInput() {
        #expect(AuralisEthereumAddress.normalized(nil) == nil)
        #expect(AuralisEthereumAddress.normalized("") == nil)
        #expect(AuralisEthereumAddress.normalized("wallet: 0xabcdef1234567890abcdef1234567890abcdef12") == nil)
        #expect(AuralisEthereumAddress.normalized("0xabcdef1234567890abcdef1234567890abcdef1") == nil)
        #expect(AuralisEthereumAddress.normalized("0xabcdef1234567890abcdef1234567890abcdef1z") == nil)
        #expect(AuralisEthereumAddress.normalized("vitalik.eth") == nil)
    }

    @Test("account store delegates address normalization to canonical model")
    func accountStoreUsesCanonicalAddressNormalization() {
        #expect(
            AccountStore.validateAddressInput("ABCDEF1234567890ABCDEF1234567890ABCDEF12")
                == .valid("0xabcdef1234567890abcdef1234567890abcdef12")
        )
        #expect(AccountStore.normalizeAddress("0XABCDEF1234567890ABCDEF1234567890ABCDEF12") == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(AccountStore.validateAddressInput("wallet: 0xabcdef1234567890abcdef1234567890abcdef12") == .invalidFormat)
    }
}

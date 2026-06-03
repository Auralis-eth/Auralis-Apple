import AccountsCore
import AuralisPrimaryModels
import Foundation
import Testing

@Suite
struct EthereumAddressTests {
    @Test(
        "normalizes supported wallet address input to lowercase 0x form",
        arguments: [
            "  0xABCDEF1234567890ABCDEF1234567890ABCDEF12  ",
            "ABCDEF1234567890ABCDEF1234567890ABCDEF12",
            "0XABCDEF1234567890ABCDEF1234567890ABCDEF12"
        ]
    )
    func normalizesWalletAddressInput(input: String) {
        #expect(AuralisEthereumAddress.normalized(input) == "0xabcdef1234567890abcdef1234567890abcdef12")
    }

    @Test("AuralisEthereumAddress rawValue initializer normalizes the canonical form")
    func rawValueInitializerNormalizesCanonicalForm() {
        #expect(
            AuralisEthereumAddress(rawValue: "0XABCDEF1234567890ABCDEF1234567890ABCDEF12")?.rawValue
                == "0xabcdef1234567890abcdef1234567890abcdef12"
        )
    }

    @Test(
        "rejects non-address input without partial extraction",
        arguments: [
            nil,
            "",
            "wallet: 0xabcdef1234567890abcdef1234567890abcdef12",
            "0xabcdef1234567890abcdef1234567890abcdef1",
            "0xabcdef1234567890abcdef1234567890abcdef1z",
            "vitalik.eth"
        ] as [String?]
    )
    func rejectsInvalidWalletAddressInput(input: String?) {
        #expect(AuralisEthereumAddress.normalized(input) == nil)
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

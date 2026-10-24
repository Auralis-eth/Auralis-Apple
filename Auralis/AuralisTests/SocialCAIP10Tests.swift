@testable import Auralis
import Foundation
import Testing

@Suite("Social CAIP-10 identity")
struct SocialCAIP10Tests {
    private let address = "0x1234567890abcdef1234567890ABCDEF12345678"

    @Test("Builds a lowercase eip155 CAIP-10 for a valid EVM address and chain")
    func buildsEIP155() {
        #expect(SocialCAIP10.eip155(address: address, chainID: 1) == "eip155:1:" + address.lowercased())
        #expect(SocialCAIP10.eip155(address: address, chainID: 8453) == "eip155:8453:" + address.lowercased())
    }

    @Test("Rejects malformed addresses and non-positive chain ids")
    func rejectsInvalid() {
        #expect(SocialCAIP10.eip155(address: "", chainID: 1) == nil)
        #expect(SocialCAIP10.eip155(address: "0x1234", chainID: 1) == nil)          // too short
        #expect(SocialCAIP10.eip155(address: "1234567890abcdef1234567890abcdef12345678", chainID: 1) == nil) // no 0x
        #expect(SocialCAIP10.eip155(address: "0x" + String(repeating: "z", count: 40), chainID: 1) == nil)   // non-hex
        #expect(SocialCAIP10.eip155(address: address, chainID: 0) == nil)
    }

    @Test("EVM address validation")
    func evmAddressValidation() {
        #expect(SocialCAIP10.isEVMAddress(address))
        #expect(!SocialCAIP10.isEVMAddress("0xABC"))
        #expect(!SocialCAIP10.isEVMAddress("nope"))
    }

    @MainActor
    @Test("participantID uses the wallet CAIP-10 when available, else the stable local fallback")
    func participantIDResolution() {
        #expect(SocialAssembly.participantID(address: address, chainID: 1) == "eip155:1:" + address.lowercased())

        // No wallet / observe-only → stable per-install fallback (not a CAIP-10).
        let fallback = SocialAssembly.participantID(address: nil, chainID: nil)
        #expect(!fallback.hasPrefix("eip155:"))
        #expect(SocialAssembly.participantID(address: "", chainID: 1) == fallback)
        #expect(SocialAssembly.participantID(address: address, chainID: nil) == fallback)
    }
}

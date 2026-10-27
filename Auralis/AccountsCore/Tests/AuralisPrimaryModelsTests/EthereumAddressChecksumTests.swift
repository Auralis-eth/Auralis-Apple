import AuralisPrimaryModels
import Testing

/// Pins the EIP-55 implementation to the reference vectors published with the EIP, which is also what
/// validates the Keccak-256 port underneath it.
struct EthereumAddressChecksumTests {
    private static let referenceAddresses = [
        "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
        "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
        // vitalik.eth — the seed address the On-Chain Watch operator ships with.
        "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    ]

    @Test("checksummed form matches the EIP-55 reference vectors", arguments: referenceAddresses)
    func checksummedMatchesReferenceVectors(expected: String) throws {
        let address = try #require(AuralisEthereumAddress(expected.lowercased()))

        #expect(address.checksummed == expected)
    }

    @Test("reference vectors classify as valid", arguments: referenceAddresses)
    func referenceVectorsAreValid(address: String) {
        #expect(AuralisEthereumAddress.checksumState(of: address) == .valid)
    }

    @Test("a single case-flipped letter fails the checksum")
    func caseFlippedLetterIsInvalid() {
        // `0xd8dA…` with the second letter of the body flipped: still 40 valid hex characters, still
        // mixed case, so only the checksum can catch it.
        #expect(AuralisEthereumAddress.checksumState(of: "0xd8Da6BF26964aF9D7eEd9e03E53415D37aA96045") == .invalid)
    }

    @Test("single-case addresses carry no checksum to verify")
    func singleCaseAddressesAreUnchecksummed() {
        #expect(
            AuralisEthereumAddress.checksumState(of: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045") == .unchecksummed
        )
        #expect(
            AuralisEthereumAddress.checksumState(of: "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045") == .unchecksummed
        )
    }

    @Test("non-addresses are malformed rather than unchecksummed")
    func nonAddressesAreMalformed() {
        #expect(AuralisEthereumAddress.checksumState(of: nil) == .malformed)
        #expect(AuralisEthereumAddress.checksumState(of: "") == .malformed)
        #expect(AuralisEthereumAddress.checksumState(of: "0xnot-an-address") == .malformed)
        // 39 hex characters — one short.
        #expect(AuralisEthereumAddress.checksumState(of: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA9604") == .malformed)
    }

    @Test("a checksummed address still normalizes for storage and comparison")
    func checksummedAddressStillNormalizes() throws {
        let address = try #require(AuralisEthereumAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"))

        #expect(address.rawValue == "0xd8da6bf26964af9d7eed9e03e53415d37aa96045")
        #expect(address.checksummed == "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
    }
}

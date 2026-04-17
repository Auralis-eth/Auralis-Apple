@testable import Auralis
import Foundation
import Testing

@Suite struct EOAccountTests {
    @Test("phase 0 defaults preserve the current address behavior while filling metadata")
    func defaultsPreserveCurrentBehavior() {
        let beforeCreation = Date()
        let account = EOAccount(address: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12", access: .readonly)

        #expect(account.address == "0xABCDEF1234567890ABCDEF1234567890ABCDEF12")
        #expect(account.access?.canSign == false)
        #expect(account.name == "Account 0xAB")
        #expect(account.source == .manualEntry)
        #expect(account.lastSelectedAt == nil)
        #expect(account.trackedNFTCount == 0)
        #expect(account.addedAt >= beforeCreation)
        #expect(account.mostRecentActivityAt == account.addedAt)
    }

    @Test("most recent activity is driven by lastSelectedAt when present")
    func mostRecentActivityUsesSelectionTimestamp() {
        let addedAt = Date(timeIntervalSince1970: 100)
        let lastSelectedAt = Date(timeIntervalSince1970: 200)
        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            source: .guestPass,
            addedAt: addedAt,
            lastSelectedAt: lastSelectedAt,
            trackedNFTCount: 14
        )

        #expect(account.source == .guestPass)
        #expect(account.trackedNFTCount == 14)
        #expect(account.mostRecentActivityAt == lastSelectedAt)
    }

    @Test("decoding older payloads falls back to phase 0 metadata defaults")
    func decodingLegacyPayloadBackfillsDefaults() throws {
        let legacyJSON = """
        {
          "address": "0x1234567890abcdef1234567890abcdef12345678",
          "access": {
            "readonly": {}
          },
          "name": "Legacy"
        }
        """

        let account = try JSONDecoder().decode(EOAccount.self, from: Data(legacyJSON.utf8))

        #expect(account.address == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(account.name == "Legacy")
        #expect(account.source == .manualEntry)
        #expect(account.addedAt == .distantPast)
        #expect(account.lastSelectedAt == nil)
        #expect(account.trackedNFTCount == 0)
    }
}

import AuralisPrimaryModels
import Foundation
import NFTDomain
import NFTKit
import Testing

@Suite
struct NFTKitTests {
    @Test("refresh scope normalizes account input and rejects empty scopes")
    func refreshScopeNormalizesAccountInput() throws {
        let scope = try #require(
            NFTRefreshScope(
                accountAddress: " 0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD ",
                chain: .baseMainnet
            )
        )

        #expect(scope.accountAddress == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(scope.chain == .baseMainnet)
        #expect(NFTRefreshScope(accountAddress: "   ", chain: .ethMainnet) == nil)
    }

    @Test("refresh state computes fresh and stale TTL boundaries deterministically")
    func refreshStateComputesFreshnessBoundaries() {
        let computer = NFTRefreshStateComputer(refreshTTL: 60)
        let account = "0x1234567890abcdef1234567890abcdef12345678"
        let refreshedAt = Date(timeIntervalSince1970: 1_704_067_200)

        computer.markRefreshSucceeded(for: account, chain: .ethMainnet, at: refreshedAt)

        #expect(computer.isFresh(for: account, chain: .ethMainnet, referenceDate: refreshedAt.addingTimeInterval(60)))
        #expect(computer.isStale(for: account, chain: .ethMainnet, referenceDate: refreshedAt.addingTimeInterval(61)))
        #expect(computer.lastSuccessfulRefreshAt(for: account, chain: .ethMainnet) == refreshedAt)
    }
}

@testable import Auralis
import Foundation
import Testing

@Suite
struct NFTRefreshStateComputerTests {
    @Test("tracks success timestamps per account and chain scope")
    @MainActor
    func tracksPerScopeTimestamps() {
        let computer = NFTRefreshStateComputer(refreshTTL: 300)
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        computer.markRefreshSucceeded(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            at: firstDate
        )
        computer.markRefreshSucceeded(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            at: secondDate
        )

        #expect(
            computer.lastSuccessfulRefreshAt(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            ) == firstDate
        )
        #expect(
            computer.lastSuccessfulRefreshAt(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet
            ) == secondDate
        )
    }

    @Test("computes freshness across TTL boundaries")
    @MainActor
    func computesFreshnessUsingTTL() {
        let computer = NFTRefreshStateComputer(refreshTTL: 60)
        let refreshDate = Date(timeIntervalSince1970: 100)
        computer.markRefreshSucceeded(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            at: refreshDate
        )

        #expect(
            computer.isFresh(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                referenceDate: Date(timeIntervalSince1970: 159)
            )
        )
        #expect(
            computer.isStale(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                referenceDate: Date(timeIntervalSince1970: 161)
            )
        )
    }

    @Test("reset clears tracked refresh state")
    @MainActor
    func resetClearsState() {
        let computer = NFTRefreshStateComputer(refreshTTL: 60)
        computer.markRefreshSucceeded(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        computer.reset()

        #expect(
            computer.lastSuccessfulRefreshAt(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            ) == nil
        )
    }
}

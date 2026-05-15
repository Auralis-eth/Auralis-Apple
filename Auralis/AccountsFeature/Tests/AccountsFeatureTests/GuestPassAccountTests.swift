import AccountsFeature
import Testing

@Suite
struct GuestPassAccountTests {
    @Test("curated guest passes stay deterministic and selectable")
    func curatedGuestPassesAreStable() {
        let accounts = GuestPassAccount.accounts

        #expect(accounts.count == 4)
        #expect(accounts.map(\.address).contains("0x9266f125fb2ecb730d9953b46de9c32e2fa83e4a"))
        #expect(accounts.allSatisfy { !$0.title.isEmpty })
        #expect(accounts.allSatisfy { $0.metadata.count == 3 })
    }

    @Test("role image uses stable account-derived choices")
    func roleImageIsStable() {
        let account = GuestPassAccount.accounts[1]

        #expect(["shippingbox.fill", "headphones"].contains(account.roleImage))
        #expect(account.roleImage == GuestPassAccount.accounts[1].roleImage)
    }
}

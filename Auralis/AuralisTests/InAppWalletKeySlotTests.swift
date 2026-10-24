@testable import Auralis
import Foundation
import Testing

/// Pins the wrapping-key **generation resolution** that `InAppWalletKeystore`'s re-wrap migration
/// (F-101) rests on.
///
/// The Keychain I/O itself is not injectable here, so what these tests cover is the part that carries
/// the correctness argument and can be reasoned about without a Secure Enclave: *which* generation is
/// treated as authoritative for a given set of item presences. That is the whole crash-safety claim —
/// a half-written new generation must never shadow an intact old one — and it is a pure function.
///
/// What these tests deliberately do **not** cover, so the gap is not mistaken for coverage: that the
/// Enclave actually mints a `.biometryAny` key, that a re-wrapped seed opens under it, and that the
/// prompt behaviour is unchanged. Those require a signed build on hardware and belong in device QA.
@Suite("In-app wallet key slot resolution")
struct InAppWalletKeySlotTests {
    private typealias Keystore = InAppWalletKeystore
    private typealias Slot = InAppWalletKeystore.KeySlot

    /// Presence lookup backed by an explicit set of "these accounts exist".
    private func presence(
        present: Set<String>,
        indeterminate: Set<String> = []
    ) -> (String) -> Keystore.ItemPresence {
        { account in
            if indeterminate.contains(account) { return .indeterminate }
            return present.contains(account) ? .present : .absent
        }
    }

    private func complete(_ slot: Slot) -> Set<String> {
        [slot.sealedSeed, slot.publicKey, slot.enclaveKey]
    }

    // MARK: - Resolution order

    @Test("a wallet with only legacy material resolves to the legacy slot")
    func legacyOnlyResolvesToLegacy() {
        let resolved = Keystore.liveSlot(presence: presence(present: complete(.legacy)))
        #expect(resolved == .legacy)
    }

    @Test("a migrated wallet resolves to the biometryAny slot")
    func migratedResolvesToModernSlot() {
        let resolved = Keystore.liveSlot(presence: presence(present: complete(.biometryAny)))
        #expect(resolved == .biometryAny)
    }

    /// The window between writing the new sealed seed and deleting the old slot. Both are complete;
    /// the *newly written* one must win, because it is the one the seed was just re-sealed under.
    @Test("with both generations complete the newer one wins")
    func bothCompletePrefersNewer() {
        let resolved = Keystore.liveSlot(
            presence: presence(present: complete(.legacy).union(complete(.biometryAny)))
        )
        #expect(resolved == .biometryAny)
    }

    // MARK: - The crash-safety property

    /// **The property the whole migration design exists for.** A crash after provisioning the new
    /// wrapping key but before the new sealed seed is written leaves a g2 key with no g2 blob. If that
    /// partial slot were treated as live, `unsealSeed` would try to open the *old* blob with the *new*
    /// key and no biometric could ever recover the wallet. It must be skipped entirely.
    @Test("a half-written migration does not shadow the intact legacy slot")
    func partialMigrationDoesNotShadowLegacy() {
        let partial = complete(.legacy).union([Slot.biometryAny.enclaveKey, Slot.biometryAny.publicKey])
        let resolved = Keystore.liveSlot(presence: presence(present: partial))

        #expect(resolved == .legacy, "a g2 slot missing its sealed seed must not be chosen")
    }

    /// The mirror case: a sealed seed with no wrapping key is equally unopenable.
    @Test("a slot with a sealed seed but no wrapping key is not live")
    func sealedSeedWithoutKeyIsNotLive() {
        let orphanBlob = complete(.legacy).union([Slot.biometryAny.sealedSeed])
        let resolved = Keystore.liveSlot(presence: presence(present: orphanBlob))

        #expect(resolved == .legacy)
    }

    @Test("no material at all resolves to no slot")
    func noMaterialResolvesToNil() {
        #expect(Keystore.liveSlot(presence: presence(present: [])) == nil)
    }

    /// An unreadable Keychain must not make a slot look openable — that would let a generation whose
    /// items merely could not be read shadow one that genuinely is intact.
    @Test("an indeterminate item does not make a slot complete")
    func indeterminateDoesNotCompleteASlot() {
        let resolved = Keystore.liveSlot(
            presence: presence(
                present: complete(.legacy).union([Slot.biometryAny.enclaveKey, Slot.biometryAny.publicKey]),
                indeterminate: [Slot.biometryAny.sealedSeed]
            )
        )
        #expect(resolved == .legacy)
    }

    // MARK: - Slot completeness

    @Test("a software-only slot is complete, for the simulator fallback")
    func softwareKeyAlsoCompletesASlot() {
        #expect(
            Keystore.isSlotComplete(
                sealedSeed: .present,
                publicKey: .present,
                enclaveKey: .absent,
                softwareKey: .present
            )
        )
    }

    @Test("a slot missing its public half is not complete")
    func missingPublicHalfIsNotComplete() {
        #expect(
            Keystore.isSlotComplete(
                sealedSeed: .present,
                publicKey: .absent,
                enclaveKey: .present,
                softwareKey: .absent
            ) == false
        )
    }

    // MARK: - Presence collapsing across generations

    /// `hasConfirmedWallet` routes the user, so any affirmative presence must win.
    @Test("one present generation makes the collapsed presence present")
    func presentWinsOverAbsent() {
        #expect(Keystore.collapsedPresence([.absent, .present]) == .present)
    }

    /// `hasWallet` guards writes and must fail closed: an unreadable generation cannot read as "no
    /// wallet", or `createWallet()` would seal a second seed over material it merely could not read.
    @Test("an indeterminate generation poisons an otherwise-absent answer")
    func indeterminateBeatsAbsent() {
        #expect(Keystore.collapsedPresence([.absent, .indeterminate]) == .indeterminate)
    }

    @Test("all absent collapses to absent")
    func allAbsentIsAbsent() {
        #expect(Keystore.collapsedPresence([.absent, .absent]) == .absent)
    }

    // MARK: - Account naming

    /// The legacy slot's names are the ones already on disk in shipped installs. Changing any of them
    /// silently orphans an existing wallet — the app would report "no wallet" for key material it still
    /// holds — so they are pinned against literals rather than against the constants themselves.
    @Test("legacy account names are frozen on-disk identifiers")
    func legacyAccountNamesAreFrozen() {
        #expect(Slot.legacy.sealedSeed == "wallet-sealed-seed")
        #expect(Slot.legacy.enclaveKey == "wallet-enclave-keyagreement")
        #expect(Slot.legacy.softwareKey == "wallet-software-keyagreement")
        #expect(Slot.legacy.publicKey == "wallet-enclave-public")
    }

    @Test("the two generations share no account name")
    func generationsDoNotCollide() {
        #expect(Set(Slot.legacy.allAccounts).isDisjoint(with: Set(Slot.biometryAny.allAccounts)))
    }

    /// `deleteWallet()` iterates this, so a generation missing from it would survive removal and keep
    /// `hasWallet` reporting `true` — leaving a wallet that cannot be used or re-created.
    @Test("every generation is reachable for deletion")
    func allGenerationsAreEnumerated() {
        #expect(Slot.allNewestFirst.count == 2)
        #expect(Slot.allNewestFirst.first == .biometryAny, "resolution order must be newest first")
        #expect(Slot.allNewestFirst.contains(.legacy))
    }
}

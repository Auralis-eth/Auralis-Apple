import Foundation
import ReceiptsCore
import Security

/// `Sendable` because it crosses an actor boundary on every throw — the store is an actor and every
/// caller is another one — matching its sibling ``ReceiptSigningKeyStoreError``.
public enum ReceiptIntegrityHeadStoreError: Error, Equatable, Sendable {
    case operationFailed(operation: String, status: OSStatus)
    /// A stored anchor's bytes are not UTF-8, so the Keychain item is not one this package wrote.
    ///
    /// There is no encoding counterpart: writing went through `hash.data(using: .utf8)` and a guard
    /// on its optional result, but UTF-8 encoding a Swift `String` cannot fail, so the case that
    /// guard threw was unreachable. ``saveHead(_:for:)`` now uses the non-failable `Data(_.utf8)`.
    case dataDecodingFailed
}

public protocol ReceiptIntegrityHeadStoring: Sendable {
    func loadHead(for accountKey: String) async throws -> String?
    func loadAllHeads() async throws -> [String: String]
    func saveHead(_ hash: String, for accountKey: String) async throws
    func clearHead(for accountKey: String) async throws
    /// Clears the per-account anchors **and** the ledger high-water mark. Both halves, because the
    /// only caller is `resetAll()`, which restarts `sequenceID` allocation at 1 — leaving the mark
    /// behind would make an honest reset read as a ledger missing every receipt it ever had.
    func clearAllHeads() async throws

    /// The highest `sequenceID` this ledger is known to have reached, or `nil` if no mark was ever
    /// written (a ledger predating the mark, or a store restored without its `ThisDeviceOnly` items).
    ///
    /// Durable state held *outside* the row store, which is what lets it say anything at all: every
    /// other integrity check reads only the surviving rows, so none of them can see a deletion that
    /// takes the high-water mark with it.
    ///
    /// **This is best-effort detection, not a security control.** What it feeds is
    /// ``ReceiptIntegrityVerificationResult/completenessAdvisory`` — a note for a person or a log —
    /// and it is deliberately kept out of every verdict. The reasoning is on
    /// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``
    /// and worth reading before relying on this for anything: the item is unauthenticated, its
    /// absence is uninformative, and neither property can be fixed from inside this package.
    ///
    /// It does have one verdict-affecting consequence, indirectly: the append path allocates above the
    /// mark, so a deletion's freed sequence IDs are never reissued and the resulting hole *is*
    /// row-derived and permanent. That is the strongest thing the mark buys.
    func loadLedgerHighWaterMark() async throws -> Int?

    /// Raises the mark to `sequenceID`. **Monotonic: an implementation must never lower it.**
    ///
    /// The monotonicity is what keeps the mark's observation stable, but be clear about what it does
    /// and does not buy: it binds *this* API, not the Keychain item. An attacker who can write the
    /// Keychain bypasses this method entirely and can set any value — which is one of the reasons the
    /// mark informs rather than gates.
    ///
    /// An existing value this store cannot *decode* is not treated as a floor to honour, so a corrupt
    /// item is replaced rather than permanently blocking every later write. The decision about
    /// whether a write is licensed at all belongs to the caller: see
    /// `ReceiptPersistenceStore.performAppend(_:)`, which will not mint a mark over a non-empty
    /// ledger, precisely so this cannot be used to manufacture agreement with a truncated one.
    func saveLedgerHighWaterMark(_ sequenceID: Int) async throws

    /// The highest ``ReceiptIntegrityEnvelopeVersion`` any build has written into this ledger, or
    /// `nil` if none was ever recorded.
    ///
    /// **This one is not advisory — it carries a verdict**, which makes it different from
    /// ``loadLedgerHighWaterMark()`` despite living in the same place.
    ///
    /// `verifyIntegrity()` cannot recompute the chain hash of a row declaring an envelope version this
    /// build does not implement, and reports it unattested rather than tampered so a *downgraded*
    /// install can still read and export the history a newer build wrote. That concession was
    /// unbounded, and unbounded it was a full bypass: the version column is itself part of the row, so
    /// an attacker with SwiftData write access **alone** could raise it on any row, and from then on
    /// nothing checked that row's `chainHash` against its contents at all. They could rewrite a
    /// receipt's `summary`, `mode` and `isSuccess` in place, or splice a fabricated row in with a
    /// `chainHash`/`signature` pair replayed from a real one — both landed on `.unattested`, which
    /// ``ReceiptIntegrityVerificationResult/isValid`` accepts, so the result travelled inside the
    /// manifest-signed archive and the standalone verifier agreed.
    ///
    /// This is the durable evidence that closes it, and it works because it is the one thing the
    /// attacker in that model cannot forge: the concession is granted only when a build *on this
    /// device* recorded having written that version. A genuine downgrade finds the floor the newer
    /// build raised, so it still reads `.unattested`; a store-only attacker cannot raise it, so a
    /// version above the floor is `.tampered`.
    ///
    /// `nil` falls back to the old permissive behaviour, deliberately and for the reason the mark's
    /// absence does: a store restored without its `ThisDeviceOnly` items, or a ledger predating this
    /// item, legitimately has no floor. Reaching that state on purpose means deleting a Keychain item,
    /// which is already the "can write both stores" attacker `isValid` concedes by design.
    func loadHighestEnvelopeVersion() async throws -> Int?

    /// Records that this build has written `version` into the ledger. **Monotonic: an implementation
    /// must never lower it.**
    ///
    /// Unlike ``saveLedgerHighWaterMark(_:)`` this is written unconditionally on every append, and the
    /// difference is worth being precise about. The mark cannot be minted over a non-empty ledger
    /// because its value is derived from the rows, so writing it could launder a deletion. This value
    /// is a *constant of the running build* — `ReceiptIntegrityEnvelopeVersion.current` — and is
    /// derived from nothing an attacker controls, so there is no equivalent laundering to worry about.
    func saveHighestEnvelopeVersion(_ version: Int) async throws
}

// No default implementation for the two requirements above, deliberately, and it was tried first.
//
// A protocol-extension default is a silent hole twice over. It disables a control for any conformer
// that forgets — the same footgun as the defaulted signer on ``ReceiptPersistenceStore/signer`` — and
// worse, a default sharing a name with an actor's own member creates an overload set where
// `try await store.loadHighestEnvelopeVersion()` on the *concrete* type binds to the throwing default
// rather than the actor's member. Measured while building this: a store that had recorded nothing
// reported `1`. Tests reach for concrete doubles constantly, so that is a default which makes tests
// state the opposite of the truth. Every conformer implements both, and the compiler says so.

public actor KeychainReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    public static let storageDecisionIdentifier = "AuralisReceiptIntegrityHeadService"
    /// A service of its own rather than a reserved account inside the head service.
    ///
    /// ``loadAllHeads()`` and ``clearAllHeads()`` query the head service *wholesale*, so a mark
    /// stored alongside the anchors would come back as an account named `"ledger"` — and
    /// `verifyIntegrity()` treats a protected head with no persisted receipts as tampering, so every
    /// verify would report an anchor for a wallet that does not exist. Separating the namespaces is
    /// what keeps the mark out of the anchor set; the tradeoff is that ``clearAllHeads()`` has to
    /// delete from both, which it does.
    public static let highWaterMarkStorageDecisionIdentifier = "AuralisReceiptLedgerHighWaterMarkService"

    private let service: String
    private let highWaterMarkService: String
    private let highWaterMarkAccount = "ledger"
    /// A second account inside the mark's service, not a third service. ``clearAllHeads()`` deletes
    /// that whole service, so a reset clears this alongside the mark.
    ///
    /// That is *not* a neutral outcome for this value, unlike for the mark: an absent floor is the
    /// permissive case, so clearing it briefly widens what a planted row can claim. Handled at the
    /// caller — `ReceiptPersistenceStore.performResetAll()` re-records the current version straight
    /// after — rather than by exempting this account here, so a reset still leaves nothing behind that
    /// was derived from the deleted history.
    private let envelopeVersionAccount = "envelope-version"
    private let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    public init() {
        self.service = Self.storageDecisionIdentifier
        self.highWaterMarkService = Self.highWaterMarkStorageDecisionIdentifier
    }

    /// A store over suffixed service names, for the tests that exercise the *real* Keychain.
    ///
    /// Those tests have to call ``clearAllHeads()`` to start from a known state, and against the
    /// production service names that is a destructive operation aimed at whatever install shares the
    /// keychain: deleting a real ledger's anchors and mark makes `verifyIntegrity()` report
    /// `.invalid("persisted receipts without protected heads")` for every account past its genesis
    /// receipt, permanently, with `resetAll()` — destroying the history — as the only way out. Access
    /// groups keep that apart in practice on this repo's hosts; a test lane should not be relying on
    /// that to avoid wiping production state.
    ///
    /// `internal`, so no shipping code can select a namespace. Not a migration seam: anchors written
    /// under a suffix are invisible to the production store by design.
    init(serviceNamespace: String) {
        self.service = "\(Self.storageDecisionIdentifier).\(serviceNamespace)"
        self.highWaterMarkService = "\(Self.highWaterMarkStorageDecisionIdentifier).\(serviceNamespace)"
    }

    public func loadHead(for accountKey: String) throws -> String? {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(
            baseQuery(accountKey: accountKey).merging(
                [
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            &dataTypeRef
        )

        switch status {
        case errSecSuccess:
            guard let data = dataTypeRef as? Data,
                  let hash = String(data: data, encoding: .utf8) else {
                throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
            }
            return hash
        case errSecItemNotFound:
            return nil
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "load", status: status)
        }
    }

    public func loadAllHeads() throws -> [String: String] {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(
            serviceQuery().merging(
                [
                    kSecReturnAttributes as String: true,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            &dataTypeRef
        )

        switch status {
        case errSecSuccess:
            guard let items = dataTypeRef as? [[String: Any]] else {
                throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
            }

            var heads: [String: String] = [:]
            for item in items {
                guard let accountKey = item[kSecAttrAccount as String] as? String,
                      let data = item[kSecValueData as String] as? Data,
                      let hash = String(data: data, encoding: .utf8) else {
                    throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
                }
                heads[accountKey] = hash
            }
            return heads
        case errSecItemNotFound:
            return [:]
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "loadAll", status: status)
        }
    }

    public func saveHead(_ hash: String, for accountKey: String) throws {
        let data = Data(hash.utf8)

        let status = SecItemAdd(
            baseQuery(accountKey: accountKey).merging(
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: accessibility
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            nil
        )

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery(accountKey: accountKey) as CFDictionary,
                [
                    kSecValueData as String: data,
                    // Re-asserted on update, not only on add. An anchor that somehow exists with
                    // weaker accessibility would otherwise keep it for the life of the install, and
                    // `ThisDeviceOnly` is what makes a missing anchor after a restore mean "another
                    // device wrote this" rather than nothing at all.
                    kSecAttrAccessible as String: accessibility
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "update", status: updateStatus)
            }
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "save", status: status)
        }
    }

    public func clearHead(for accountKey: String) throws {
        let status = SecItemDelete(baseQuery(accountKey: accountKey) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "delete", status: status)
        }
    }

    public func clearAllHeads() throws {
        // The mark first. `resetAll()` calls this *after* deleting the rows, so if the second delete
        // throws the ledger must be left in the recoverable direction: no mark with stale anchors is
        // reported as tampering and fixed by running the reset again, whereas a surviving mark over
        // zero rows would read as "missing every receipt" — and re-running the reset would not clear
        // it, because the throw would happen before this line on every attempt.
        try deleteAll(in: highWaterMarkService, operation: "deleteHighWaterMark")
        try deleteAll(in: service, operation: "deleteAll")
    }

    public func loadLedgerHighWaterMark() throws -> Int? {
        try loadMonotonicInteger(account: highWaterMarkAccount, operation: "HighWaterMark")
    }

    public func saveLedgerHighWaterMark(_ sequenceID: Int) throws {
        try saveMonotonicInteger(
            sequenceID,
            account: highWaterMarkAccount,
            operation: "HighWaterMark"
        )
    }

    public func loadHighestEnvelopeVersion() throws -> Int? {
        try loadMonotonicInteger(account: envelopeVersionAccount, operation: "EnvelopeVersion")
    }

    public func saveHighestEnvelopeVersion(_ version: Int) throws {
        try saveMonotonicInteger(version, account: envelopeVersionAccount, operation: "EnvelopeVersion")
    }

    private func loadMonotonicInteger(account: String, operation: String) throws -> Int? {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(
            markServiceQuery(account: account).merging(
                [
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            &dataTypeRef
        )

        switch status {
        case errSecSuccess:
            guard let data = dataTypeRef as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let value = Int(text) else {
                throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(
                operation: "load\(operation)",
                status: status
            )
        }
    }

    private func saveMonotonicInteger(_ value: Int, account: String, operation: String) throws {
        // Read-then-write with no suspension in between: these are synchronous `SecItem` calls inside
        // an actor, so nothing can interleave and lose a concurrent raise. Making either half `async`
        // would reintroduce exactly that torn read-modify-write.
        //
        // `try?` on the read, not `try`. A plain `try` meant a stored item that will not decode —
        // non-UTF-8 bytes, or anything `Int(_:)` rejects — failed the *write* as well, so the bad item
        // could never be replaced: every verification afterwards reported completeness unconfirmed,
        // permanently, with `resetAll()` as the only way out. An item this device cannot parse is not
        // a floor it can honour, so it is overwritten rather than allowed to pin the ledger. The
        // caller decides whether a write is licensed at all — see
        // `ReceiptPersistenceStore.performAppend(_:)`, which will not mint a mark over a non-empty
        // ledger precisely so this cannot be used to launder a deletion.
        if let existing = try? loadMonotonicInteger(account: account, operation: operation),
           existing >= value {
            return
        }
        let data = Data(String(value).utf8)

        let status = SecItemAdd(
            markServiceQuery(account: account).merging(
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: accessibility
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            nil
        )

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                markServiceQuery(account: account) as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: accessibility
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ReceiptIntegrityHeadStoreError.operationFailed(
                    operation: "update\(operation)",
                    status: updateStatus
                )
            }
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(
                operation: "save\(operation)",
                status: status
            )
        }
    }

    private func deleteAll(in service: String, operation: String) throws {
        let status = SecItemDelete(serviceQuery(service: service) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: operation, status: status)
        }
    }

    private func baseQuery(accountKey: String) -> [String: Any] {
        var query = serviceQuery()
        query[kSecAttrAccount as String] = accountKey
        return query
    }

    /// The mark service, which holds every ledger-wide scalar this store keeps — the high-water mark
    /// and the envelope-version floor — one per account name. Kept out of the *anchor* service
    /// because ``loadAllHeads()`` and ``clearAllHeads()`` query that one wholesale, so anything stored
    /// there comes back as an account anchor and `verifyIntegrity()` reports a protected head for a
    /// wallet that does not exist.
    private func markServiceQuery(account: String) -> [String: Any] {
        var query = serviceQuery(service: highWaterMarkService)
        query[kSecAttrAccount as String] = account
        return query
    }

    private func serviceQuery(service: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

public actor InMemoryReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    private var heads: [String: String] = [:]
    private var ledgerHighWaterMark: Int?
    private var highestEnvelopeVersion: Int?

    public init() { }

    public func loadHead(for accountKey: String) -> String? {
        heads[accountKey]
    }

    public func loadAllHeads() -> [String: String] {
        heads
    }

    public func saveHead(_ hash: String, for accountKey: String) {
        heads[accountKey] = hash
    }

    public func clearHead(for accountKey: String) {
        heads.removeValue(forKey: accountKey)
    }

    public func clearAllHeads() {
        heads.removeAll()
        ledgerHighWaterMark = nil
        highestEnvelopeVersion = nil
    }

    public func loadLedgerHighWaterMark() -> Int? {
        ledgerHighWaterMark
    }

    /// Monotonic, matching the Keychain implementation's contract rather than merely assigning — a
    /// test double that let the mark fall backwards would quietly pass tests the real store fails.
    public func saveLedgerHighWaterMark(_ sequenceID: Int) {
        ledgerHighWaterMark = max(ledgerHighWaterMark ?? 0, sequenceID)
    }

    /// `nil` until something records one, which is the state that matters: it models a restored store
    /// or a ledger predating the item, where the concession on
    /// ``ReceiptIntegrityHeadStoring/loadHighestEnvelopeVersion()`` is deliberately permissive. Taking
    /// the protocol's strict default here instead would make this double disagree with the real
    /// Keychain store on the one case the fallback exists for.
    public func loadHighestEnvelopeVersion() -> Int? {
        highestEnvelopeVersion
    }

    public func saveHighestEnvelopeVersion(_ version: Int) {
        highestEnvelopeVersion = max(highestEnvelopeVersion ?? 0, version)
    }
}

import AuralisPrimaryModels
import Foundation
import OperatorsFeature
import OSLog
import AuralisReceipts

/// Backs the built-in operators with the app's *real* local activity: the append-only receipt ledger.
/// Requires no external network authority (ADR-010, P1-701..703) — it only reads on-device records and
/// filters them to the operator's scope (watchlist address, active identity, or research query).
public struct ReceiptBackedOperatorDataSource: OperatorDataSource {
    private let receiptStore: any ReceiptStore

    public init(receiptStore: any ReceiptStore) {
        self.receiptStore = receiptStore
    }

    public func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] {
        // Pull a wider window than requested, then narrow to the operator's scope.
        let window = max(limit * 4, 100)
        let records: [ReceiptRecord]
        do {
            records = try await receiptStore.latest(limit: window)
        } catch {
            // Logged rather than discarded. This was `(try? …) ?? []`, so an unreadable ledger and a
            // genuinely quiet one produced the same empty result — and the operators built on top of
            // it go on to write a *durable artifact* from it. A Research Brief or On-Chain Watch
            // report stating "no recent activity" is a claim about the account, and it must not be
            // how a storage fault presents itself with nothing recorded anywhere.
            //
            // `OperatorDataSource.recentActivity` is non-throwing, so the empty result still has to
            // be returned; this at least leaves the fault traceable. Same posture as
            // ``RuntimeHost/routineEventSignals(now:)`` for an unreadable artifact store.
            Self.logger.error(
                """
                Failed to read the receipt ledger for an operator run; this operator will report no \
                recent activity, which is indistinguishable from a genuinely quiet ledger: \
                \(error.localizedDescription, privacy: .public)
                """
            )
            records = []
        }
        var activity = records.map(Self.map)

        if !request.watchlist.isEmpty {
            // `WatchTarget.chainKey`, the same canonical key `OperatorArtifactComposer.matches` and
            // `WatchTarget.id` use. Exact `lowercased()` comparison made this the *narrow* half of
            // one filter: `chain.inScope` canonicalizes aliases, so a watch scoped `"ethereum"`
            // passed its check and then matched nothing in a ledger recording `"eth-mainnet"` — and
            // because this narrowing runs *before* the composer, fixing only the composer left the
            // bug fully reachable. The watch wrote a durable artifact and receipt saying "_No recent
            // observed activity._" against a ledger full of matching events.
            //
            // The address half is `WatchTarget.addressKey` for exactly the same reason, and it was
            // the half left behind when the chain half was fixed: a bare `lowercased()` folds case
            // but not whitespace, so a padded watchlist entry matched nothing here and the ledger's
            // events for that account were dropped before the composer ever saw them — the same
            // silent "reported clean" failure, one axis over.
            let scopes = Set(request.watchlist.map {
                WatchScope(
                    chain: WatchTarget.chainKey($0.chain),
                    address: WatchTarget.addressKey($0.address)
                )
            })
            activity = activity.filter { entry in
                guard let chain = entry.chain.map(WatchTarget.chainKey),
                      let address = entry.address.map(WatchTarget.addressKey) else { return false }
                return scopes.contains(WatchScope(chain: chain, address: address))
            }
        }

        if let identity = request.identityID?.lowercased(), !identity.isEmpty {
            activity = activity.filter { entry in
                entry.identityID?.lowercased() == identity
            }
        }

        if let query = request.query?.lowercased(), !query.isEmpty {
            let terms = query.split(whereSeparator: { $0 == " " }).map(String.init)
            activity = activity.filter { entry in
                let haystack = (entry.title + " " + entry.detail).lowercased()
                return terms.contains { haystack.contains($0) }
            }
        }

        return Array(activity.prefix(limit))
    }

    private static func map(_ record: ReceiptRecord) -> ObservedActivity {
        let values = record.details.values
        return ObservedActivity(
            title: record.summary,
            detail: "\(record.scope) · \(record.trigger)",
            occurredAt: record.createdAt,
            chain: string(in: values, preferring: chainKeyPriority, keysContaining: ["chain"]),
            address: string(in: values, preferring: addressKeyPriority, keysContaining: ["address"])
                ?? addressLike(in: values),
            identityID: string(in: values, preferring: identityKeyPriority, keysContaining: ["identity", "account"]),
            sourceReceiptID: record.id,
            isSuccess: record.isSuccess
        )
    }

    private static let logger = Logger(subsystem: "com.auralis.runtime", category: "operator-data-source")

    private struct WatchScope: Hashable {
        let chain: String
        let address: String
    }

    /// Payload keys that name the subject of an activity, in the order they are preferred.
    ///
    /// Explicit and ordered because the extraction below used to iterate the payload dictionary and
    /// take the first key whose name merely contained `"address"`. Swift seeds `Dictionary` hashing
    /// per process, so a receipt carrying more than one candidate resolved to a *different* one on
    /// each launch — and `approveSpending` carries three (`token`, `spender`, `owner`, all
    /// well-formed addresses). Since `OperatorArtifactComposer` matches watch targets by address
    /// alone, the same watch report attributed the same receipt to the watched account in one launch
    /// and not the next, which is not something a reproducible audit trail can afford.
    ///
    /// Ordered by whose address the activity is *about*: the account that acted or was acted upon
    /// ahead of the delegate it granted or the token contract involved.
    ///
    /// - Note: A single activity still surfaces a single address, so a watch on a receipt's *second*
    ///   address (a watch on the `spender` of an approval, say) is not matched. That is a separate
    ///   limitation of ``ObservedActivity``'s shape, not of the ordering here.
    private static let addressKeyPriority = ["address", "owner", "from", "to", "spender", "token"]
    private static let chainKeyPriority = ["chain", "chainid"]
    private static let identityKeyPriority = ["identityid", "identity", "account"]

    /// The value under the first matching key: exact (case-insensitive) matches from `preferred`
    /// first, then keys that merely *contain* one of `substrings`.
    ///
    /// Both passes walk the keys in sorted order, so a payload with several matching keys resolves
    /// the same way on every launch and in every process.
    private static func string(
        in values: [String: ReceiptJSONValue],
        preferring preferred: [String],
        keysContaining substrings: [String]
    ) -> String? {
        let sortedKeys = values.keys.sorted()
        for candidate in preferred {
            for key in sortedKeys where key.lowercased() == candidate {
                if let string = nonEmptyString(values[key]) { return string }
            }
        }
        for key in sortedKeys {
            let lowered = key.lowercased()
            guard substrings.contains(where: { lowered.contains($0) }) else { continue }
            if let string = nonEmptyString(values[key]) { return string }
        }
        return nil
    }

    /// Any string value that looks like a 0x-prefixed 40-hex address, as a fallback. Scanned in
    /// sorted key order for the same reproducibility reason as ``addressKeyPriority``.
    private static func addressLike(in values: [String: ReceiptJSONValue]) -> String? {
        for key in values.keys.sorted() {
            guard let string = nonEmptyString(values[key]) else { continue }
            let hex = string.hasPrefix("0x") ? String(string.dropFirst(2)) : string
            if hex.count == 40, hex.allSatisfy(\.isHexDigit) { return string }
        }
        return nil
    }

    private static func nonEmptyString(_ value: ReceiptJSONValue?) -> String? {
        guard case let .string(string)? = value, !string.isEmpty else { return nil }
        return string
    }
}

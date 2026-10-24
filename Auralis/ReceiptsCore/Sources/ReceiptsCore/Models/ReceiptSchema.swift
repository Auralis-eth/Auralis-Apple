import Foundation

/// The field contract for a persisted receipt.
///
/// Carries no version. Receipts are append-only facts that outlive the build that wrote them, so a
/// recorded record-shape version was the right instinct — but it only earns its keep once there is
/// history written under an *older* shape to interpret. Nothing has shipped, so every row in every
/// store was written by the current build, and a `schemaVersion` column would have been a constant
/// persisted on every receipt, committed to the integrity hash, and branched on by readers that can
/// only ever see one value. Reintroduce it in the same change that first needs to read two shapes,
/// where the migration it enables can be written and tested against real divergent rows.
///
/// Distinct from ``ReceiptProvenanceExport/currentVersion``, which versions the *export envelope*
/// (the manifest, hashes, and trust anchor) — that one crosses a trust boundary to an independent
/// verifier, which is a genuinely different problem from reading back your own storage.
public enum ReceiptSchema {
    /// Returns human-readable problems with the receipt-shaping values a caller declares, or an
    /// empty array when they satisfy this schema.
    ///
    /// Deliberately narrow. A receipt's identity, ordering, integrity, scope, and trigger are all
    /// assigned by the store and the governance sink, not by the caller, so demanding them here
    /// would fail every legitimate run. What a caller *does* contribute is the parameter set that
    /// gets rendered into the record's readable plan, and a blank key there produces a receipt row
    /// no one can interpret — which is exactly the kind of unreadable governance record this check
    /// exists to keep out of an append-only ledger.
    public static func problems(inDeclared parameters: [String: String]) -> [String] {
        var problems: [String] = []
        if parameters.keys.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            problems.append("receipt payload keys must not be blank")
        }
        return problems
    }
}

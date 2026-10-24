import AuralisPrimaryModels
import PolicyCore
import ReceiptsCore

/// The user's persisted crypto mode, for assembly parameters that need a *correct* default.
///
/// Several assembly entry points take a `modeProvider` so the caller can supply the live `ModeState`.
/// Those parameters used to default to a hardcoded `{ .observe }`, which is the wrong kind of default
/// for a governance input: a call site that forgot the argument compiled clean and then wrote
/// `.observe` into receipts' hashed `mode` column — and fed it to the policy gate — while the app was
/// actually in Operate. The failure is silent and the evidence it corrupts is the ledger.
///
/// Rather than forbid the defaulted call, the default is made right. This reads the same persisted
/// `app.mode` key every `ModeState` does, so an omitted argument degrades to "the user's real mode"
/// instead of to a fabricated one. Callers that hold a live `ModeState` should still pass it — this is
/// a floor, not a replacement.
@MainActor
enum PersistedCryptoMode {
    /// A long-lived reader. `ModeState.mode` is a stored property assigned at construction rather than
    /// a live `@AppStorage` read, so ``current`` refreshes it before every read.
    private static let state = ModeState()

    static var current: CryptoMode {
        state.refreshFromStorage()
        return state.mode
    }

    static var currentReceiptMode: ReceiptMode { current.receiptMode }

    /// Persists `mode`, for the matching default on a `cryptoModeSetter` parameter.
    ///
    /// A setter default of `{ _ in }` silently discarded every mode change made through whichever
    /// object graph took the default — this writes it where the next ``current`` will see it.
    ///
    /// Refreshes first because `ModeState.setMode` early-returns when the new mode equals its *cached*
    /// `mode`, and only ``current`` ever refreshes that cache. Without this, a sequence of
    /// `current` (caches `observe`) → another instance writes `operate` → `set(.observe)` would see
    /// `observe == observe`, return early, and never persist the demotion — silently dropping a move
    /// to the safer mode.
    static func set(_ mode: CryptoMode) {
        state.refreshFromStorage()
        state.setMode(mode)
    }
}

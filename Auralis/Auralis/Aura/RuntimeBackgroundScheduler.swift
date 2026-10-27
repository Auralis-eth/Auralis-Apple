import AuralisPrimaryPersistence
import Foundation
import OSLog
import AuralisReceipts
import RuntimeKit
import SwiftData

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Drives the operator scheduling engine from a background app-refresh task (P1-601/602).
///
/// The `.backgroundTask(.appRefresh(...))` scene modifier in `AuralisApp` registers the handler; this
/// type performs the run and reschedules. Registration/Info.plist are in place; actual background
/// *firing* is validated on device (the simulator does not fire real BG tasks).
enum RuntimeBackgroundScheduler {
    static let taskIdentifier = "com.auralis.runtime.refresh"
    private static let logger = Logger(subsystem: "com.auralis", category: "RuntimeBackgroundScheduler")

    /// Runs every installed routine whose trigger is due, then every enabled ritual whose trigger is
    /// due (P1-SOCIAL-102 auto-scheduling). Kill-switch aware via the host's pause gate (paused runs
    /// short-circuit to no-ops inside the engine).
    @MainActor
    static func runDueRoutines(host: RuntimeHost, now: Date = .now) async {
        let signals = await host.routineEventSignals(now: now)
        await host.runDueRoutines(
            now: now,
            eventSignals: signals
        )
        // Cancellation checked between the two phases, not inside them: BGTask expiration should stop
        // the *next* unit of work rather than abandon one mid-flight, which is what would risk a side
        // effect without its receipt.
        guard !Task.isCancelled else { return }
        await host.runDueRituals(
            now: now,
            staleSignal: signals.staleSignal,
            approvalPendingSignal: signals.approvalPendingSignal
        )
    }

    /// This task's own `ModelContainer` and `ModeState`, built once per process and reused.
    ///
    /// The container cannot be shared with the app's: that one is created by SwiftUI's
    /// `.modelContainer(for:)` scene modifier, which exposes no handle, and the refresh handler can
    /// be invoked with no scene alive. So this path opens a second one — the two-host topology
    /// `SharedCoordinationStores` (F-23) and ``RuntimePauseStatePersistence`` are written around.
    ///
    /// What matters is that it is opened **once**. It used to be built fresh on every invocation,
    /// and `RuntimeAssembly.sharedHost` memoizes on `ObjectIdentifier(modelContext.container)` —
    /// so a brand-new container was a guaranteed cache miss, every refresh constructed another
    /// `RuntimeHost`, and `hostsByContainer` retains hosts for the life of the process with nothing
    /// ever removing them. The retain chain is complete (static dictionary → host → receipt store →
    /// `ModelContext` → `ModelContainer`), so nothing was collectable: an hourly refresh added a
    /// fully-built runtime — event bus, scheduling engine, tool registry, lease registry, plus open
    /// connections to *both* the primary store and the operator runtime store — on every run, and
    /// `flushEventCheckpoints()` then walked all of them on every backgrounding.
    @MainActor
    private static var sharedBackgroundContainer: ModelContainer?

    @MainActor
    private static var sharedBackgroundModeState: ModeState?

    /// Builds a shared host from the primary store and runs due routines. Invoked by the scene's
    /// background-task handler.
    @MainActor
    static func runInBackground() async {
        defer { scheduleNextRefresh() }
        guard let container = resolveBackgroundContainer() else { return }
        // Memoized alongside the container because the host captures these closures and outlives this
        // call — and because `RuntimeAssembly.sharedHost` ignores the mode plumbing on a cache hit, so
        // the first instance is the one that sticks.
        //
        // `refreshFromStorage()` on every run is what makes that safe. `ModeState.mode` is a stored
        // property assigned at construction, *not* a live read of `@AppStorage`: a memoized instance
        // would otherwise report the mode as of the first background run forever, so a user who
        // switched to Observe in the foreground would still have background work evaluated — and
        // receipts stamped, in a hashed column — as Operate.
        let modeState = sharedBackgroundModeState ?? {
            let state = ModeState()
            sharedBackgroundModeState = state
            return state
        }()
        modeState.refreshFromStorage()

        let host = RuntimeAssembly.sharedHost(
            modelContext: ModelContext(container),
            cryptoModeProvider: { modeState.mode },
            cryptoModeSetter: { modeState.setMode($0) }
        )
        // Honour BGTask expiration, which SwiftUI surfaces as task cancellation. Without this the run
        // continues until the OS kills it, which can land between a side effect and its receipt.
        guard !Task.isCancelled else { return }
        await runDueRoutines(host: host)
    }

    /// The memoized background container, opened on first use.
    ///
    /// A failure to open is deliberately **not** cached: the usual causes (device locked under data
    /// protection, storage pressure) are transient, and caching `nil` would disable background
    /// routines for the rest of the process over a condition that clears on its own.
    ///
    /// `makeContainer` is injectable so the memoization can be asserted against an in-memory store.
    /// It has to be: a test that opened the real primary store contended with the rest of the
    /// app test plan under its parallel simulator clones and took the clone down with it.
    @MainActor
    static func resolveBackgroundContainer(
        // Through the shared configuration for the reason given on
        // ``PrimaryStoreSchema/configuration(isStoredInMemoryOnly:)``: the default opts this store
        // into SwiftData's CloudKit mirroring, which this schema cannot satisfy.
        makeContainer: () throws -> ModelContainer = {
            try ModelContainer(
                for: PrimaryStoreSchema.schema,
                configurations: PrimaryStoreSchema.configuration()
            )
        }
    ) -> ModelContainer? {
        if let sharedBackgroundContainer { return sharedBackgroundContainer }
        guard let container = try? makeContainer() else {
            logger.error("Background refresh could not open the primary store; skipping this run.")
            return nil
        }
        sharedBackgroundContainer = container
        return container
    }

    /// Clears the memoized container and mode state so a test can exercise the first-open path.
    /// Process-wide statics, so a suite that uses them must reset on both sides.
    @MainActor
    static func resetBackgroundStateForTesting() {
        sharedBackgroundContainer = nil
        sharedBackgroundModeState = nil
    }

    /// Submits the next background app-refresh request. Safe no-op if BackgroundTasks is unavailable.
    ///
    /// Submitting replaces any pending request for the same identifier rather than adding one, so an
    /// unconditional submit on every foreground launch let a user who opens the app more often than
    /// `interval` push the background run out indefinitely — each launch reset `earliestBeginDate` to
    /// now + an hour, and routines that only run in the background would never fire. An existing
    /// request that is already due sooner is therefore left alone.
    static func scheduleNextRefresh(after interval: TimeInterval = 3_600) {
        #if canImport(BackgroundTasks) && os(iOS)
        let earliest = Date(timeIntervalSinceNow: interval)
        Task {
            let pending = await BGTaskScheduler.shared.pendingTaskRequests()
            let existing = pending
                .compactMap { $0 as? BGAppRefreshTaskRequest }
                .first { $0.identifier == taskIdentifier }
            // A pending request with no `earliestBeginDate` can fire at any time — strictly sooner
            // than anything we would submit — so it is also left in place.
            if let existing, (existing.earliestBeginDate ?? .distantPast) <= earliest {
                return
            }

            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = earliest
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                logger.error("Unable to schedule runtime refresh: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }
}

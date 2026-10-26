import Foundation
import ReceiptsCore
import RuntimeCore
import SwiftData
import Testing

@testable import ReceiptStorage

/// The ledger lock is not reentrant, and for a while the thing standing between a misplaced call and
/// a hang was `assert(!LedgerLock.isHeld)`. That had two defects, and a field crash found both.
///
/// 1. It *trapped*. An NFT refresh appending `nft.refresh.started` died on this assertion in a test
///    run — a debug crash in front of a person for a telemetry write whose own recorder treats
///    failure as best-effort, and in release the same path got the self-wait the assert was warning
///    about. Neither configuration did what the comment said it did.
/// 2. The condition was wider than the hazard. `isHeld` was one process-wide task-local, while
///    `ReceiptPersistenceStore` is memoized *per `ModelContainer`*, and task-locals are inherited by
///    every unstructured `Task {}` spawned under a locked body — so the marker outlived its body and
///    spoke for stores that had nothing to do with it. Throwing on the bare boolean would have
///    started discarding receipts that work today.
///
/// So the marker now names its store and its acquisition, and these cases pin both halves: a genuine
/// self-wait is refused promptly, and an inherited-but-dead or foreign marker is not.
@MainActor
struct ReceiptLedgerReentrancyTests {
    private static let account = "0x1111111111111111111111111111111111111111"

    private func makeStore() throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: try ReceiptStorageTestModelContainers.context().container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            // Explicit and held for the instance's lifetime, so `.verified` is reachable and anything
            // less is a real regression rather than a missing identity.
            signer: SoftwareReceiptSigner()
        )
    }

    private func draft(_ kind: String) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 100),
            category: "accounts",
            kind: kind,
            correlationID: nil,
            payload: ReceiptPayload(values: [:]),
            actorDetail: .system,
            authorityDetail: nil,
            timelineAccountAddress: Self.account
        )
    }

    // MARK: - A genuine self-wait

    /// The enclosing label is deliberately *not* `.append`, so the diagnostic is asserted to name
    /// both ends of the nesting rather than one operation twice.
    @Test("an append from inside a live ledger body is refused, naming both operations")
    func reentrantAppendIsRefused() async throws {
        let store = try makeStore()
        let nested = draft("nested")

        let thrown = await #expect(throws: ReceiptLedgerReentrancyError.self) {
            try await store.withLedgerLock(.verifyIntegrity) {
                _ = try await store.append(nested)
            }
        }

        #expect(thrown?.attemptedOperation == .append)
        #expect(thrown?.enclosingOperation == .verifyIntegrity)
    }

    @Test("a refused append leaves no partial receipt behind")
    func refusedAppendWritesNothing() async throws {
        let store = try makeStore()
        let nested = draft("nested")

        _ = await #expect(throws: ReceiptLedgerReentrancyError.self) {
            try await store.withLedgerLock(.verifyIntegrity) {
                _ = try await store.append(nested)
            }
        }

        let records = try await store.allRecords()
        #expect(records.isEmpty, "a refused acquisition persisted a row")
    }

    /// The refusal happens before the tail queue or the token counter is touched, so the thing to
    /// prove is that the *next* ordinary caller is unaffected — a guard that stranded the queue
    /// would trade a hang inside the body for a hang everywhere after it.
    @Test("the ledger queue stays usable after a refusal")
    func ledgerSurvivesARefusal() async throws {
        let store = try makeStore()
        let nested = draft("nested")

        _ = await #expect(throws: ReceiptLedgerReentrancyError.self) {
            try await store.withLedgerLock(.verifyIntegrity) {
                _ = try await store.append(nested)
            }
        }

        let record = try await store.append(draft("after-refusal"))
        #expect(record.accountSequenceID == 1)

        let result = try await store.verifyIntegrity()
        #expect(
            result.status == .verified,
            "ledger not fully attested after a refusal: \(result.failureReason ?? "-")"
        )
    }

    // MARK: - Markers that are inherited rather than held

    /// The case the crash actually looked like.
    ///
    /// A task spawned inside a locked body inherits the marker and keeps it for its whole life, long
    /// after the body returns — in the field, by way of a `modelContext.save()` notification waking
    /// unrelated work. Such a task is not waiting on anything it owns: it queues behind the tail like
    /// any other caller. Refusing it would discard a real receipt to prevent a hang that cannot
    /// happen, so it must proceed.
    ///
    /// Gated rather than raced: an ungated spawn can reach the lock either side of the body's return,
    /// which is exactly the flaky test that would later be deleted instead of fixed.
    @Test("a marker inherited by a task that outlives its body does not block the append")
    func escapedMarkerStillAppends() async throws {
        let store = try makeStore()
        let escaped = draft("escaped")
        let gate = Gate()

        let spawned: Task<ReceiptRecord, Error> = try await store.withLedgerLock(.verifyIntegrity) {
            Task {
                await gate.wait()
                return try await store.append(escaped)
            }
        }

        // Only now, with the enclosing acquisition finished and its token retired.
        await gate.open()
        let record = try await spawned.value
        #expect(record.accountSequenceID == 1)
    }

    /// The liveness set has to mean "a body is running", and it did not: registration used to happen
    /// in `withLedgerLock` before the queue wait and was released only when the whole call returned,
    /// so it also covered callers that had not started and bodies that had already finished.
    ///
    /// That is not bookkeeping. A refusal needs a marker *and* a live acquisition, and the marker
    /// escapes its body — the premise this whole mechanism is built on. An acquisition that stays
    /// registered after its body returns therefore makes an escaped marker name a live acquisition
    /// with nothing behind it, and the escaped task's append is refused for a self-wait that is over.
    /// `escapedMarkerStillAppends` passes either way because it gates the spawn until after the
    /// enclosing call returns; the ungated case its own comment describes — "either side of the
    /// body's return" — is the broken half, and it is a scheduling race, so this invariant is what
    /// can actually be pinned.
    ///
    /// Asserted from inside a running body against a second caller that is provably queued: `second`
    /// has to reach the lock to get into the queue at all, and the yields are bounded, so a count
    /// that stays at one is a real answer rather than a test that finished too early.
    @Test("a caller still waiting its turn is not registered as a live acquisition")
    func queuedCallerIsNotRegisteredAsLive() async throws {
        let store = try makeStore()
        let bodyStarted = Gate()
        let release = Gate()

        let firstBody = Task {
            try await store.withLedgerLock(.verifyIntegrity) {
                await bodyStarted.open()
                await release.wait()

                var observed = await store.liveLedgerAcquisitionsForTesting.count
                // Bounded, because the queued caller's arrival on the actor is a hop this test does
                // not control. Sixty-four yields is far past it; what the bound buys is a failure
                // that says "stayed at one" rather than hanging.
                for _ in 0..<64 {
                    guard observed == 1 else {
                        break
                    }
                    await Task.yield()
                    observed = await store.liveLedgerAcquisitionsForTesting.count
                }
                return observed
            }
        }

        // Only once the first body is provably running, so the second caller can only ever be the
        // queued one. It carries no inherited marker of its own.
        await bodyStarted.wait()
        let second = Task { try await store.append(self.draft("queued")) }
        await release.open()

        let observed = try await firstBody.value
        #expect(
            observed == 1,
            "a caller that has not started its body was registered as a live acquisition"
        )

        // And it still gets its turn.
        let record = try await second.value
        #expect(record.accountSequenceID == 1)
    }

    /// Two stores over two containers have two independent queues, so one's locked body says nothing
    /// about the other's. The process-wide task-local used to conflate them, which mattered in tests
    /// before it mattered anywhere else: every case here builds its own container.
    @Test("one store's locked body does not block an append to a different store")
    func foreignMarkerStillAppends() async throws {
        let storeA = try makeStore()
        let storeB = try makeStore()
        let crossStore = draft("cross-store")

        let record = try await storeA.withLedgerLock(.verifyIntegrity) {
            try await storeB.append(crossStore)
        }

        #expect(record.accountSequenceID == 1)

        let recordsInA = try await storeA.allRecords()
        #expect(recordsInA.isEmpty, "the receipt landed in the wrong store")
    }
}

/// A one-shot latch, so a spawned task can be held at a known point instead of racing the thing the
/// test is trying to observe.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        let resuming = waiters
        waiters.removeAll()
        for waiter in resuming {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

import ArtifactCore
import ArtifactStorage
import Foundation
import OSLog
import SwiftData

private let migrationLogger = Logger(subsystem: "Auralis", category: "LegacyArtifactMigration")

/// Copies artifacts out of the legacy ``StoredArtifactRecord`` table into ``StoredArtifact``.
///
/// Artifacts used to be persisted by a `SwiftDataArtifactStore` declared in this package, as one
/// JSON blob per row. The store that reads and writes them now is `ArtifactStorage`'s — the one with
/// real columns, an external-storage body, a rollback guard on every write, and a read path that
/// refuses a row it cannot interpret rather than coercing an unknown approval state to `.draft`.
/// Two same-named types coexisted for a while; the hardened one had 21 passing tests and zero
/// production imports, while this package's weaker one was what `PersistentRuntimeHost` built.
///
/// Swapping the store over changes which *table* production reads, so artifacts already on disk
/// would simply stop appearing. This moves them across once, on first open after the upgrade.
///
/// Deliberately not a SwiftData `SchemaMigrationPlan`: the two row types are independent models in
/// one container rather than two versions of one model, and the body has to be re-encoded through
/// ``Artifact`` on the way across (the legacy blob holds the whole value; the new row holds columns
/// plus an external-storage `content`). A plain copy keeps that decode explicit and lets an
/// undecodable row be reported and skipped instead of failing the whole container open.
public enum LegacyArtifactMigration {
    /// What one migration pass did. Returned rather than logged alone so a test can assert it.
    public struct Result: Equatable, Sendable {
        /// Rows copied into ``StoredArtifact``.
        public let migratedCount: Int
        /// Rows already present under the same id in ``StoredArtifact``, left alone and deleted.
        public let skippedExistingCount: Int
        /// Rows this build could not decode. Left in place, not deleted — see ``run(in:)``.
        public let unreadableCount: Int
        /// Whether the pass hit a hard failure: a table it could not read, or a batch it could not
        /// commit.
        ///
        /// Distinct from the counts because all three of those failure paths used to return
        /// ``noLegacyRows``, which is also what a healthy second pass returns. A caller could not
        /// tell "there is nothing to migrate" from "the migration failed and every pre-upgrade
        /// artifact is still invisible" — the one state worth surfacing. The counts remain
        /// meaningful when this is `true`: batches that committed before the failure are reported,
        /// because they really are on disk.
        public let didFail: Bool

        public init(
            migratedCount: Int,
            skippedExistingCount: Int,
            unreadableCount: Int,
            didFail: Bool = false
        ) {
            self.migratedCount = migratedCount
            self.skippedExistingCount = skippedExistingCount
            self.unreadableCount = unreadableCount
            self.didFail = didFail
        }

        public static let noLegacyRows = Result(migratedCount: 0, skippedExistingCount: 0, unreadableCount: 0)

        /// A pass that moved nothing because it could not read the tables it needed.
        public static let failure = Result(
            migratedCount: 0,
            skippedExistingCount: 0,
            unreadableCount: 0,
            didFail: true
        )
    }

    /// How many legacy rows one transaction carries.
    ///
    /// Small, because the cost per row is not the row: each one is held as a stored blob, as a
    /// decoded ``Artifact``, and again as the new row's `content`, all live in the same
    /// `ModelContext` until the commit drops them. `PersistentRuntimeHost` runs this on container
    /// open, which includes a `BGTaskScheduler` launch under a tight memory limit, so a corpus of a
    /// few hundred large artifacts is a jetsam before it is a slow migration — and a jetsam commits
    /// nothing, leaves every legacy row in place, and repeats on the next launch. A permanently
    /// stalled migration, with every pre-upgrade artifact invisible the whole time.
    static let defaultBatchSize = 50

    /// Runs the migration against `container`, returning what it did.
    ///
    /// Idempotent by construction: a legacy row whose id already exists in ``StoredArtifact`` is not
    /// copied over the top of it, and every row that was dealt with is deleted. A second pass finds
    /// nothing and returns ``Result/noLegacyRows``, so this is safe to call on every launch — which
    /// it is, because there is no separate "has migrated" flag to get out of step with the data.
    ///
    /// An undecodable legacy row is *kept*. It is the one case where deleting would destroy the only
    /// copy of something this build merely failed to read — a row written by a newer build, say —
    /// and an artifact is a durable work product. It stays available to a build that understands it.
    ///
    /// Non-throwing: a migration that cannot commit must not stop the app from opening.
    ///
    /// **Committed in batches of ``defaultBatchSize``, not as one transaction**, which is a change
    /// from the original shape and does not weaken anything the original guaranteed. The unit that
    /// has to be atomic is the *row*: one artifact is one insert plus one delete of its legacy row,
    /// and those two always land in the same batch, so no batch boundary can half-copy an artifact
    /// or leave one present in both tables. A row the pass never reached is simply still in the
    /// legacy table, untouched, and the next pass picks it up verbatim — which is the same
    /// situation a second launch finds after *any* interrupted run, including the all-or-nothing
    /// one. What batching rules out is the failure the single transaction could not survive: the
    /// pass being killed before it ever commits, so every launch redoes all the work and none of it
    /// sticks. Progress is now monotonic.
    ///
    /// A batch that fails to commit is rolled back, leaving its own rows in the legacy table for
    /// the next pass, and stops the loop — the failure is almost always "this device cannot write
    /// right now", and grinding through the remaining batches would just repeat it.
    @discardableResult
    public static func run(in container: ModelContainer) -> Result {
        run(in: container, batchSize: defaultBatchSize)
    }

    /// - Parameters:
    ///   - batchSize: Rows per transaction. Test seam; production uses ``defaultBatchSize``.
    ///   - stoppingAfterBatches: Abandons the pass after this many committed batches, modelling the
    ///     real interruption this batching exists for — the process being killed mid-migration, not
    ///     an error it can catch. Test seam; production is `.max`.
    @discardableResult
    static func run(
        in container: ModelContainer,
        batchSize: Int,
        stoppingAfterBatches maximumBatches: Int = .max
    ) -> Result {
        let context = ModelContext(container)

        // Counted before anything is read, because this is the answer on every launch after the
        // first and it must not cost a scan of the artifact table to reach.
        do {
            guard try context.fetchCount(FetchDescriptor<StoredArtifactRecord>()) > 0 else {
                return .noLegacyRows
            }
        } catch {
            migrationLogger.error(
                "Could not read the legacy artifact table; artifacts written before the storage change stay invisible until this succeeds: \(error.localizedDescription, privacy: .public)"
            )
            return .failure
        }

        var existingIDs: Set<UUID>
        do {
            // Only the ids are read, so only the ids are fetched: this used to materialise every
            // `StoredArtifact` row — external-storage bodies and all — to call `.map(\.id)` on them.
            var existingDescriptor = FetchDescriptor<StoredArtifact>()
            existingDescriptor.propertiesToFetch = [\.id]
            existingIDs = Set(try context.fetch(existingDescriptor).map(\.id))
        } catch {
            migrationLogger.error(
                "Could not read the current artifact table, so the migration cannot tell what is already there: \(error.localizedDescription, privacy: .public)"
            )
            return .failure
        }

        var migrated = 0
        var skipped = 0
        var unreadable = 0
        var batchesRun = 0
        // Rows this pass deliberately left in the legacy table are the only ones a later fetch can
        // see again, so they — and nothing else — are what the window has to step over. Everything
        // the pass handled was deleted and committed, so it is gone from the next page.
        var leftInPlace = 0
        let decoder = JSONDecoder()

        while batchesRun < maximumBatches {
            var descriptor = FetchDescriptor<StoredArtifactRecord>(
                // Any total order will do; `id` is one the window cannot see shift under it.
                sortBy: [SortDescriptor(\StoredArtifactRecord.id, order: .forward)]
            )
            descriptor.fetchOffset = leftInPlace
            descriptor.fetchLimit = batchSize

            let legacyRows: [StoredArtifactRecord]
            do {
                legacyRows = try context.fetch(descriptor)
            } catch {
                migrationLogger.error(
                    "Could not read the legacy artifact table; artifacts written before the storage change stay invisible until this succeeds: \(error.localizedDescription, privacy: .public)"
                )
                return Result(
                    migratedCount: migrated,
                    skippedExistingCount: skipped,
                    unreadableCount: unreadable,
                    didFail: true
                )
            }
            guard !legacyRows.isEmpty else { break }

            var batchMigrated = 0
            var batchSkipped = 0
            var batchUnreadable = 0
            var batchMigratedIDs: [UUID] = []

            for row in legacyRows {
                // Decoded through `Artifact` rather than copied column-to-column: the legacy row
                // holds the whole value as a blob, and fields the new table keeps as real columns
                // (version, approval state, provenance, related receipts) only exist inside it.
                guard let artifact = try? decoder.decode(Artifact.self, from: row.data) else {
                    batchUnreadable += 1
                    migrationLogger.error(
                        "Left legacy artifact row \(row.id, privacy: .public) in place: this build cannot decode it."
                    )
                    continue
                }
                if existingIDs.contains(artifact.id) {
                    batchSkipped += 1
                    context.delete(row)
                    continue
                }
                guard let stored = try? StoredArtifact(artifact: artifact) else {
                    batchUnreadable += 1
                    migrationLogger.error(
                        "Left legacy artifact row \(row.id, privacy: .public) in place: it decoded but could not be re-encoded."
                    )
                    continue
                }
                context.insert(stored)
                context.delete(row)
                // Tracked as the pass goes, not just at the start: once a batch is committed, two
                // legacy rows carrying the same artifact id must not both be inserted.
                batchMigratedIDs.append(artifact.id)
                batchMigrated += 1
            }

            do {
                try context.save()
            } catch {
                // Only this batch is undone; earlier batches are committed and stay that way. Its
                // rows are therefore still in the legacy table, which is exactly where the next
                // pass expects to find anything that did not make it across.
                context.rollback()
                migrationLogger.error(
                    "Artifact migration could not commit a batch after \(migrated, privacy: .public) row(s); the rest of the legacy rows are unchanged and the next launch will retry: \(error.localizedDescription, privacy: .public)"
                )
                return Result(
                    migratedCount: migrated,
                    skippedExistingCount: skipped,
                    unreadableCount: unreadable,
                    didFail: true
                )
            }

            // Counted only once the batch is on disk, so a reported count is always a committed one.
            migrated += batchMigrated
            skipped += batchSkipped
            unreadable += batchUnreadable
            leftInPlace += batchUnreadable
            existingIDs.formUnion(batchMigratedIDs)
            batchesRun += 1
        }

        if migrated > 0 || skipped > 0 || unreadable > 0 {
            migrationLogger.log(
                "Migrated \(migrated, privacy: .public) artifact(s) to the hardened store; \(skipped, privacy: .public) already present, \(unreadable, privacy: .public) left as written."
            )
        }
        return Result(migratedCount: migrated, skippedExistingCount: skipped, unreadableCount: unreadable)
    }
}

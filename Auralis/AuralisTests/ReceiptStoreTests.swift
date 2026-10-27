@testable import Auralis
import AuralisCrypto
import AuralisTestSupport
import Foundation
import AuralisReceipts
import SwiftData
import Testing

@Suite(.tags(.swiftdata))
struct ReceiptStoreTests {
    /// Fixture builder for the store tests below. These tests are about sequencing, ordering, and the
    /// hash chain, so attribution is fixed here rather than restated at every call site. P0.5-602 makes
    /// `actorDetail`/`authorityDetail` required on ``ReceiptDraft`` so that *production* writers have to
    /// name them; `nil` authority is the honest fixture value because these appends never pass a policy
    /// gate, so no authority is ever resolved for them.
    private func draft(
        createdAt: Date,
        category: String,
        kind: String,
        correlationID: String? = nil,
        payload: ReceiptPayload,
        timelineAccountAddress: String? = nil
    ) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: createdAt,
            category: category,
            kind: kind,
            correlationID: correlationID,
            payload: payload,
            actorDetail: .system,
            authorityDetail: nil,
            timelineAccountAddress: timelineAccountAddress
        )
    }

    @MainActor
    private func makeStore() throws -> SwiftDataReceiptStore {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        return SwiftDataReceiptStore(
            modelContext: context
        )
    }

    @MainActor
    private func makeStoreWithInspectableIntegrityHeads() throws -> (
        store: SwiftDataReceiptStore,
        context: ModelContext,
        headStore: InMemoryReceiptIntegrityHeadStore
    ) {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: container,
                integrityHeadStore: headStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
        return (store, context, headStore)
    }

    @Test("append assigns monotonic sequence IDs and preserves caller-provided fields")
    @MainActor
    func appendAssignsSequenceIDs() async throws {
        let store = try makeStore()

        let first = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                correlationID: "flow-1",
                payload: ReceiptPayload(values: ["address": .string("0xabc")])
            )
        )
        let second = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.selected",
                correlationID: "flow-1",
                payload: ReceiptPayload(values: ["address": .string("0xabc")])
            )
        )

        #expect(first.sequenceID == 1)
        #expect(second.sequenceID == 2)
        #expect(first.category == "accounts")
        #expect(second.kind == "account.selected")
        #expect(second.correlationID == "flow-1")
        #expect(first.accountSequenceID == 1)
        #expect(second.accountSequenceID == 2)
        #expect(first.payloadHash.isEmpty == false)
        #expect(first.previousReceiptHash == "GENESIS")
        #expect(first.chainHash.isEmpty == false)
        #expect(second.previousReceiptHash == first.chainHash)
    }

    @Test("latest returns bounded receipts ordered by newest timestamp with sequence fallback for ties")
    @MainActor
    func latestUsesStableDescendingOrdering() async throws {
        let store = try makeStore()

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.started",
                payload: ReceiptPayload(values: [:])
            )
        )
        let second = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.progress",
                payload: ReceiptPayload(values: [:])
            )
        )
        let third = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 300),
                category: "networking",
                kind: "refresh.finished",
                payload: ReceiptPayload(values: [:])
            )
        )

        let latest = try await store.latest(limit: 2)

        #expect(latest.map(\.sequenceID) == [third.sequenceID, second.sequenceID])
        #expect(latest.map(\.kind) == ["refresh.finished", "refresh.progress"])
    }

    @Test("correlation reads stay bounded and scoped to the caller-provided correlation ID")
    @MainActor
    func correlationReadsAreBounded() async throws {
        let store = try makeStore()

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "networking",
                kind: "refresh.started",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )
        let matchingNewest = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.finished",
                correlationID: "refresh-1",
                payload: ReceiptPayload(values: [:])
            )
        )
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 300),
                category: "networking",
                kind: "refresh.started",
                correlationID: "refresh-2",
                payload: ReceiptPayload(values: [:])
            )
        )

        let correlated = try await store.receipts(forCorrelationID: "refresh-1", limit: 1)

        #expect(correlated.count == 1)
        let receipt = try #require(correlated.first)
        #expect(receipt.sequenceID == matchingNewest.sequenceID)
        #expect(receipt.correlationID == "refresh-1")
    }

    @Test("exportAll returns every receipt in deterministic ascending order for JSON export")
    @MainActor
    func exportAllUsesDeterministicOrdering() async throws {
        let store = try makeStore()

        let first = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["step": .number(1)])
            )
        )
        let second = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["step": .number(2)])
            )
        )

        let exportedData = try await store.exportAll()
        let records = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: exportedData).records

        #expect(records.map(\.sequenceID) == [first.sequenceID, second.sequenceID])
        #expect(records.map(\.kind) == ["account.added", "account.selected"])
    }

    @Test("exportAll emits the sanitized payloads exactly as persisted")
    @MainActor
    func exportAllUsesSanitizedPersistedPayloads() async throws {
        let store = try makeStore()
        let sanitizer = DefaultReceiptPayloadSanitizer()
        let sanitizedPayload = sanitizer.sanitize(
            RawReceiptPayload(
                fields: [
                    .public("rpcURL", string: "https://rpc.example/secret", kind: .url),
                    .public("error", string: "provider failure", kind: .errorMessage)
                ]
            )
        )

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "networking",
                kind: "refresh.failed",
                payload: sanitizedPayload
            )
        )

        let exportedData = try await store.exportAll()
        let records = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: exportedData).records

        #expect(records.count == 1)
        #expect(records.first?.payload.values["rpcURL"] == .string("<redacted-url>"))
        #expect(records.first?.payload.values["error"] == .string("<redacted-error>"))
    }

    @Test("exportAll produces a signed provenance envelope verifiable against a pinned signer fingerprint")
    @MainActor
    func exportAllProducesVerifiableProvenanceEnvelope() async throws {
        let store = try makeStore()
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )

        let data = try await store.exportAll()
        let export = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        let result = try ReceiptProvenanceVerifier.verify(
            data,
            trustedSignerFingerprint: export.trustAnchor.fingerprint
        )

        #expect(export.format == ReceiptProvenanceExport.currentFormat)
        #expect(export.version == ReceiptProvenanceExport.currentVersion)
        #expect(export.manifest.recordCount == 1)
        #expect(result.isValid)
    }

    @Test("provenance verification rejects an untrusted signer and a mutated manifest")
    @MainActor
    func provenanceVerificationRejectsWrongTrustAnchorAndMutation() async throws {
        let store = try makeStore()
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )

        let data = try await store.exportAll()
        let export = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        let wrongTrust = try ReceiptProvenanceVerifier.verify(
            data,
            trustedSignerFingerprint: String(repeating: "0", count: 64)
        )
        #expect(wrongTrust.isValid == false)

        let mutatedManifest = ReceiptProvenanceManifest(
            recordCount: export.manifest.recordCount + 1,
            recordsHash: export.manifest.recordsHash,
            chainHeads: export.manifest.chainHeads
        )
        let mutatedExport = ReceiptProvenanceExport(
            records: export.records,
            manifest: mutatedManifest,
            manifestHash: export.manifestHash,
            manifestSignature: export.manifestSignature,
            trustAnchor: export.trustAnchor
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let mutationResult = try ReceiptProvenanceVerifier.verify(
            encoder.encode(mutatedExport),
            trustedSignerFingerprint: export.trustAnchor.fingerprint
        )
        #expect(mutationResult.isValid == false)
    }

    @Test("resetAll wipes the receipt store without introducing any per-item delete API")
    @MainActor
    func resetAllRemovesEverything() async throws {
        let store = try makeStore()

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "networking",
                kind: "refresh.started",
                payload: ReceiptPayload(values: [:])
            )
        )

        try await store.resetAll()

        #expect(try await store.latest(limit: 10).isEmpty)
        let exportedData = try await store.exportAll()
        let records = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: exportedData).records
        #expect(records.isEmpty)
    }

    @Test("failed integrity head writes roll back the just-persisted receipt")
    @MainActor
    func failedIntegrityHeadWriteDoesNotLeavePersistedReceipt() async throws {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: container,
                integrityHeadStore: FailingReceiptIntegrityHeadStore(failOnSave: true),
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )

        do {
            _ = try await store.append(
                draft(
                    createdAt: Date(timeIntervalSince1970: 100),
                    category: "accounts",
                    kind: "account.added",
                    payload: ReceiptPayload(values: [:])
                )
            )
            Issue.record("Expected receipt append to fail when the integrity head write fails.")
        } catch {
            #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
        }
    }

    @Test("receipt integrity verification fails when metadata is missing")
    @MainActor
    func integrityVerificationRejectsMissingMetadata() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x2222222222222222222222222222222222222222"

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        let receipt = try #require(try context.fetch(
            FetchDescriptor<StoredReceipt>(
                sortBy: [SortDescriptor(\StoredReceipt.sequenceID)]
            )
        ).first)
        receipt.payloadHash = ""
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt \(receipt.id.uuidString) is missing integrity metadata.")
    }

    /// Stripping the signature from a receipt that *was* signed is tampering.
    ///
    /// Note this is no longer the same claim as "unsigned receipts are rejected". A receipt written
    /// before provenance signing existed is legitimately unsigned, and rejecting those is what made
    /// upgrading an install invalidate its whole ledger and refuse every export — so a genuine legacy
    /// row now verifies as `.unattested` (covered in `ReceiptStorageTests`). What must still fail is
    /// *removing* signing metadata, which this constructs: the signer's public key is part of the
    /// hashed envelope, so clearing it breaks the chain hash whether or not the row's position in the
    /// chain would otherwise have grandfathered it.
    @Test("receipt integrity verification rejects a receipt whose signature was stripped")
    @MainActor
    func integrityVerificationRejectsStrippedSigningMetadata() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: [:])
            )
        )
        let receipt = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        receipt.signature = nil
        receipt.signerPublicKey = nil
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt \(receipt.id.uuidString) has an invalid chain hash.")
    }

    @Test("receipt integrity verification fails after out-of-band mutation or deletion")
    @MainActor
    func integrityVerificationDetectsTampering() async throws {
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let context = ModelContext(container)
        let store = SwiftDataReceiptStore(
            modelContext: context
        )
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )

        #expect(try await store.verifyIntegrity().isValid)

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID)]
        )
        descriptor.fetchLimit = 1
        let mutatedReceipt = try #require(context.fetch(descriptor).first)
        mutatedReceipt.summary = "mutated outside receipt store"
        try context.save()

        #expect(try await store.verifyIntegrity().isValid == false)

        try await store.resetAll()
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 200),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 201),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )

        let latestReceipt = try #require(
            context.fetch(
                FetchDescriptor<StoredReceipt>(
                    sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
                )
            ).first
        )
        context.delete(latestReceipt)
        try context.save()

        #expect(try await store.verifyIntegrity().isValid == false)
    }

    @Test("receipt integrity verification fails when every receipt for an account is deleted out of band")
    @MainActor
    func integrityVerificationDetectsFullAccountReceiptDeletion() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.selected",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        for receipt in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            context.delete(receipt)
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt integrity has protected heads without persisted receipts.")
    }

    @Test("receipt integrity verification fails when one account's receipt chain is removed")
    @MainActor
    func integrityVerificationDetectsPartialAccountReceiptDeletion() async throws {
        let (store, context, _) = try makeStoreWithInspectableIntegrityHeads()
        let firstAccountAddress = "0x1111111111111111111111111111111111111111"
        let secondAccountAddress = "0x2222222222222222222222222222222222222222"

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(firstAccountAddress)]),
                timelineAccountAddress: firstAccountAddress
            )
        )
        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 101),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(secondAccountAddress)]),
                timelineAccountAddress: secondAccountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        for receipt in try context.fetch(FetchDescriptor<StoredReceipt>()) where receipt.accountAddress == firstAccountAddress {
            context.delete(receipt)
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt integrity has protected heads without persisted receipts.")
    }

    /// A single-receipt account whose anchor is gone is **healed, not reported as tampering**, and
    /// this assertion was inverted until it was checked against the behaviour the package actually
    /// implements.
    ///
    /// It previously expected `.tampered` with "persisted receipts without protected heads". Round
    /// 10 deliberately changed that: an account holding exactly its genesis row with no anchor is
    /// indistinguishable from an append killed between the row save and the anchor write, and
    /// branding that ordinary crash window as a forged ledger made `exportAll()` refuse the history
    /// permanently. `AuralisReceipts`'s own `genesisAppendCrashWindowIsHealedNotTampering` pins the
    /// rule with the full argument, and this test is the app-hosted view of the same store.
    ///
    /// It went unnoticed for a round because nothing re-ran the app plan after Round 10, and then
    /// the CloudKit container regression made every test in this file fail before reaching an
    /// assertion at all.
    @Test("a persisted receipt that lost its protected head is healed, not reported as tampering")
    @MainActor
    func integrityVerificationHealsMissingProtectedHead() async throws {
        let (store, _, headStore) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        let genesis = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        await headStore.clearHead(for: accountAddress)

        let result = try await store.verifyIntegrity()
        #expect(result.isValid, "a genesis crash window is not tampering: \(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("without protected heads") != true,
            "\(result.failureReason ?? "-")"
        )
        // Healed in place, so the export a person came for keeps working.
        #expect(await headStore.loadHead(for: accountAddress) == genesis.chainHash)
        #expect(try await store.exportAll().isEmpty == false)
    }

    @Test("receipt integrity verification fails when a protected head does not match persisted receipts")
    @MainActor
    func integrityVerificationDetectsProtectedHeadMismatch() async throws {
        let (store, _, headStore) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        await headStore.saveHead("mismatched-protected-head", for: accountAddress)

        let result = try await store.verifyIntegrity()
        #expect(result.isValid == false)
        #expect(result.failureReason == "Receipt chain head mismatch for \(accountAddress).")
    }

    @Test("receipt integrity verification remains valid after an intentional full reset")
    @MainActor
    func integrityVerificationAcceptsIntentionalReset() async throws {
        let (store, _, _) = try makeStoreWithInspectableIntegrityHeads()
        let accountAddress = "0x1111111111111111111111111111111111111111"

        _ = try await store.append(
            draft(
                createdAt: Date(timeIntervalSince1970: 100),
                category: "accounts",
                kind: "account.added",
                payload: ReceiptPayload(values: ["address": .string(accountAddress)]),
                timelineAccountAddress: accountAddress
            )
        )
        #expect(try await store.verifyIntegrity().isValid)

        try await store.resetAll()

        #expect(try await store.verifyIntegrity().isValid)
    }
}

private actor FailingReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    struct Failure: Error { }

    let failOnSave: Bool

    init(failOnSave: Bool) {
        self.failOnSave = failOnSave
    }

    func loadHead(for accountKey: String) throws -> String? {
        nil
    }

    func loadAllHeads() throws -> [String: String] {
        [:]
    }

    func saveHead(_ hash: String, for accountKey: String) throws {
        if failOnSave {
            throw Failure()
        }
    }

    func clearHead(for accountKey: String) throws { }

    func clearAllHeads() throws {
        ledgerHighWaterMark = nil
        highestEnvelopeVersion = nil
    }

    private var ledgerHighWaterMark: Int?

    func loadLedgerHighWaterMark() throws -> Int? {
        ledgerHighWaterMark
    }

    /// Tracked rather than stubbed out, and monotonic like the real store: a double that always
    /// answered `nil` would leave every ledger built on it reporting unconfirmed completeness, so
    /// these tests would assert `.unattested` for a reason none of them is about.
    func saveLedgerHighWaterMark(_ sequenceID: Int) throws {
        if failOnSave {
            throw Failure()
        }
        ledgerHighWaterMark = max(ledgerHighWaterMark ?? 0, sequenceID)
    }

    private var highestEnvelopeVersion: Int?

    /// Tracked for the reason the mark above is: this one carries a *verdict*, not an advisory. A row
    /// declaring an envelope version above the recorded floor is `.tampered`, because raising that
    /// column is what disables the chain-hash recomputation and a store-only attacker must not be able
    /// to license that themselves. A double that always answered `nil` would leave these tests
    /// exercising the permissive fallback rather than the real path.
    func loadHighestEnvelopeVersion() throws -> Int? {
        highestEnvelopeVersion
    }

    func saveHighestEnvelopeVersion(_ version: Int) throws {
        if failOnSave {
            throw Failure()
        }
        highestEnvelopeVersion = max(highestEnvelopeVersion ?? 0, version)
    }
}

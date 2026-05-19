import AuralisPrimaryModels
import CryptoKit
import Foundation
import ReceiptsCore
import SwiftData
import SwiftDataAdapters

public struct ReceiptIntegrityVerificationResult: Equatable, Sendable {
    public let isValid: Bool
    public let failureReason: String?

    public static let valid = ReceiptIntegrityVerificationResult(isValid: true, failureReason: nil)

    public static func invalid(_ reason: String) -> ReceiptIntegrityVerificationResult {
        ReceiptIntegrityVerificationResult(isValid: false, failureReason: reason)
    }
}

@ModelActor
public actor ReceiptPersistenceStore {
    private var nextSequenceIDCache: Int?
    private var integrityHeadStore: any ReceiptIntegrityHeadStoring = KeychainReceiptIntegrityHeadStore()

    public init(
        modelContainer: ModelContainer,
        integrityHeadStore: any ReceiptIntegrityHeadStoring = KeychainReceiptIntegrityHeadStore()
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.integrityHeadStore = integrityHeadStore
    }

    public func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let nextSequenceID = try allocateSequenceID()
        let accountAddress = normalizedAccountAddress(from: receipt)
        let latestReceipt = try latestReceipt(accountAddress: accountAddress)
        let accountSequenceID = (latestReceipt?.accountSequenceID ?? 0) + 1
        let previousReceiptHash = latestReceipt?.chainHash ?? ReceiptIntegrity.genesisHash
        let payloadHash = try ReceiptIntegrity.payloadHash(for: receipt.details)
        let chainHash = try ReceiptIntegrity.chainHash(
            id: nil,
            sequenceID: nextSequenceID,
            accountSequenceID: accountSequenceID,
            createdAt: receipt.createdAt,
            actor: receipt.actor,
            mode: receipt.mode,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            accountAddress: accountAddress,
            chainRawValue: receipt.timelineChainRawValue,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash
        )
        let storedReceipt = try StoredReceipt(
            sequenceID: nextSequenceID,
            createdAt: receipt.createdAt,
            actor: receipt.actor,
            mode: receipt.mode,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            timelineAccountAddress: receipt.timelineAccountAddress,
            timelineChainRawValue: receipt.timelineChainRawValue,
            accountSequenceID: accountSequenceID,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash,
            chainHash: chainHash,
            details: receipt.details
        )

        modelContext.insert(storedReceipt)
        try modelContext.save()
        do {
            try await integrityHeadStore.saveHead(chainHash, for: ReceiptIntegrity.accountKey(accountAddress: accountAddress))
        } catch {
            try? modelContext.performRollbackSafeMutation {
                modelContext.delete(storedReceipt)
            }
            nextSequenceIDCache = nil
            throw error
        }
        return storedReceipt.asReceiptRecord()
    }

    public func resetAll() async throws {
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        let headsToRestore = latestHeads(from: receipts)

        try await integrityHeadStore.clearAllHeads()
        do {
            try modelContext.performRollbackSafeMutation {
                for receipt in receipts {
                    modelContext.delete(receipt)
                }
            }
        } catch {
            await restoreHeads(headsToRestore)
            throw error
        }
        nextSequenceIDCache = nil
    }

    public func restoreHeads(_ heads: [String: String]) async {
        for (accountKey, chainHash) in heads {
            try? await integrityHeadStore.saveHead(chainHash, for: accountKey)
        }
    }

    private func latestHeads(from receipts: [StoredReceipt]) -> [String: String] {
        var latestByAccount: [String: StoredReceipt] = [:]
        for receipt in receipts where receipt.hasCompleteIntegrityMetadata {
            let accountKey = ReceiptIntegrity.accountKey(accountAddress: receipt.accountAddress)
            if receipt.isNewerIntegrityHead(than: latestByAccount[accountKey]) {
                latestByAccount[accountKey] = receipt
            }
        }
        return latestByAccount.mapValues(\.chainHash)
    }

    public func verifyIntegrity() async throws -> ReceiptIntegrityVerificationResult {
        let receipts = try modelContext.fetch(
            FetchDescriptor<StoredReceipt>(
                sortBy: [
                    SortDescriptor(\StoredReceipt.accountAddress),
                    SortDescriptor(\StoredReceipt.accountSequenceID),
                    SortDescriptor(\StoredReceipt.sequenceID)
                ]
            )
        )

        var previousByAccount: [String: StoredReceipt] = [:]

        for receipt in receipts {
            guard receipt.hasCompleteIntegrityMetadata else {
                return .invalid("Receipt \(receipt.id.uuidString) is missing integrity metadata.")
            }

            let accountKey = ReceiptIntegrity.accountKey(accountAddress: receipt.accountAddress)
            let previousReceipt = previousByAccount[accountKey]
            let expectedAccountSequenceID = (previousReceipt?.accountSequenceID ?? 0) + 1
            guard receipt.accountSequenceID == expectedAccountSequenceID else {
                return .invalid("Receipt \(receipt.id.uuidString) has an invalid account sequence.")
            }

            let expectedPreviousHash = previousReceipt?.chainHash ?? ReceiptIntegrity.genesisHash
            guard receipt.previousReceiptHash == expectedPreviousHash else {
                return .invalid("Receipt \(receipt.id.uuidString) has an invalid previous hash.")
            }

            let expectedPayloadHash = try ReceiptIntegrity.payloadHash(for: receipt.decodedDetails())
            guard receipt.payloadHash == expectedPayloadHash else {
                return .invalid("Receipt \(receipt.id.uuidString) has an invalid payload hash.")
            }

            let expectedChainHash = try ReceiptIntegrity.chainHash(
                id: nil,
                sequenceID: receipt.sequenceID,
                accountSequenceID: receipt.accountSequenceID,
                createdAt: receipt.createdAt,
                actor: receipt.actor,
                mode: receipt.mode,
                trigger: receipt.trigger,
                scope: receipt.scope,
                summary: receipt.summary,
                provenance: receipt.provenance,
                isSuccess: receipt.isSuccess,
                correlationID: receipt.correlationID,
                accountAddress: receipt.accountAddress,
                chainRawValue: receipt.chainRawValue,
                payloadHash: receipt.payloadHash,
                previousReceiptHash: receipt.previousReceiptHash
            )
            guard receipt.chainHash == expectedChainHash else {
                return .invalid("Receipt \(receipt.id.uuidString) has an invalid chain hash.")
            }

            previousByAccount[accountKey] = receipt
        }

        let persistedHeads = previousByAccount.mapValues(\.chainHash)
        let protectedHeads = try await integrityHeadStore.loadAllHeads()
        let persistedHeadKeys = Set(persistedHeads.keys)
        let protectedHeadKeys = Set(protectedHeads.keys)
        let protectedOnlyKeys = protectedHeadKeys.subtracting(persistedHeadKeys)
        guard protectedOnlyKeys.isEmpty else {
            return .invalid("Receipt integrity has protected heads without persisted receipts.")
        }

        let persistedOnlyKeys = persistedHeadKeys.subtracting(protectedHeadKeys)
        guard persistedOnlyKeys.isEmpty else {
            return .invalid("Receipt integrity has persisted receipts without protected heads.")
        }

        for (accountKey, chainHash) in persistedHeads {
            guard protectedHeads[accountKey] == chainHash else {
                return .invalid("Receipt chain head mismatch for \(accountKey).")
            }
        }

        return .valid
    }

    private func allocateSequenceID() throws -> Int {
        if let nextSequenceIDCache {
            self.nextSequenceIDCache = nextSequenceIDCache + 1
            return nextSequenceIDCache
        }

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let nextSequenceID = (try modelContext.fetch(descriptor).first?.sequenceID ?? 0) + 1
        nextSequenceIDCache = nextSequenceID + 1
        return nextSequenceID
    }

    private func latestReceipt(accountAddress: String?) throws -> StoredReceipt? {
        let normalizedAddress = accountAddress
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.accountAddress == normalizedAddress
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.accountSequenceID, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func normalizedAccountAddress(from receipt: ReceiptDraft) -> String? {
        receipt.timelineAccountAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

@MainActor
public final class SwiftDataReceiptStore: ReceiptStore {
    private let modelContext: ModelContext
    private let persistenceStore: ReceiptPersistenceStore

    public init(
        modelContext: ModelContext,
        persistenceStore: ReceiptPersistenceStore
    ) {
        self.modelContext = modelContext
        self.persistenceStore = persistenceStore
    }

    public convenience init(
        modelContext: ModelContext,
        sequenceAllocator: ReceiptSequenceAllocator
    ) {
        self.init(
            modelContext: modelContext,
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: modelContext.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore()
            )
        )
    }

    public func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        try await persistenceStore.append(receipt)
    }

    public func latest(limit: Int) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    public func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        let correlationValue = correlationID
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.correlationID == correlationValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    public func exportAll() throws -> Data {
        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt),
                SortDescriptor(\StoredReceipt.sequenceID)
            ]
        )

        let records = try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(records)
    }

    public func resetAll() async throws {
        try await persistenceStore.resetAll()
    }

    public func verifyIntegrity() async throws -> ReceiptIntegrityVerificationResult {
        try await persistenceStore.verifyIntegrity()
    }
}

public final class ReceiptSequenceAllocator {
    public init() { }
}

@MainActor
public enum ReceiptStores {
    // These caches are keyed by long-lived shell-owned ModelContext instances.
    // We intentionally keep one receipt store and sequence allocator per context
    // rather than evicting aggressively, because churning either object would
    // break receipt ordering guarantees within that context.
    private static var cachedStores: [ObjectIdentifier: SwiftDataReceiptStore] = [:]
    private static var cachedPersistenceStores: [ObjectIdentifier: ReceiptPersistenceStore] = [:]

    public static func live(modelContext: ModelContext) -> any ReceiptStore {
        let key = ObjectIdentifier(modelContext)
        if let cachedStore = cachedStores[key] {
            return cachedStore
        }

        let store = SwiftDataReceiptStore(
            modelContext: modelContext,
            persistenceStore: persistenceStore(for: modelContext)
        )
        cachedStores[key] = store
        return store
    }

    static func persistenceStore(for modelContext: ModelContext) -> ReceiptPersistenceStore {
        let key = ObjectIdentifier(modelContext.container)
        if let cachedPersistenceStore = cachedPersistenceStores[key] {
            return cachedPersistenceStore
        }

        let newPersistenceStore = ReceiptPersistenceStore(
            modelContainer: modelContext.container,
            integrityHeadStore: KeychainReceiptIntegrityHeadStore()
        )
        cachedPersistenceStores[key] = newPersistenceStore
        return newPersistenceStore
    }
}

private extension StoredReceipt {
    var hasCompleteIntegrityMetadata: Bool {
        !payloadHash.isEmpty
            && !previousReceiptHash.isEmpty
            && !chainHash.isEmpty
    }

    func isNewerIntegrityHead(than current: StoredReceipt?) -> Bool {
        guard let current else {
            return true
        }

        return accountSequenceID > current.accountSequenceID
            || (
                accountSequenceID == current.accountSequenceID
                && sequenceID > current.sequenceID
            )
    }

    func asReceiptRecord() -> ReceiptRecord {
        ReceiptRecord(
            id: id,
            sequenceID: sequenceID,
            createdAt: createdAt,
            actor: actor,
            mode: mode,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            accountSequenceID: accountSequenceID,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash,
            chainHash: chainHash,
            details: decodedDetailsOrEmpty()
        )
    }
}

private enum ReceiptIntegrity {
    static let genesisHash = "GENESIS"

    static func accountKey(accountAddress: String?) -> String {
        guard let accountAddress, !accountAddress.isEmpty else {
            return "global"
        }
        return accountAddress.lowercased()
    }

    static func payloadHash(for payload: ReceiptPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256Hex(try encoder.encode(payload))
    }

    static func chainHash(
        id: UUID?,
        sequenceID: Int,
        accountSequenceID: Int,
        createdAt: Date,
        actor: ReceiptActor,
        mode: ReceiptMode,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        accountAddress: String?,
        chainRawValue: String?,
        payloadHash: String,
        previousReceiptHash: String
    ) throws -> String {
        let envelope = ReceiptIntegrityEnvelope(
            sequenceID: sequenceID,
            accountSequenceID: accountSequenceID,
            createdAt: createdAt.timeIntervalSince1970,
            actor: actor.rawValue,
            mode: mode.rawValue,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            accountAddress: accountAddress,
            chainRawValue: chainRawValue,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256Hex(try encoder.encode(envelope))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct ReceiptIntegrityEnvelope: Encodable {
    let sequenceID: Int
    let accountSequenceID: Int
    let createdAt: TimeInterval
    let actor: String
    let mode: String
    let trigger: String
    let scope: String
    let summary: String
    let provenance: String
    let isSuccess: Bool
    let correlationID: String?
    let accountAddress: String?
    let chainRawValue: String?
    let payloadHash: String
    let previousReceiptHash: String
}

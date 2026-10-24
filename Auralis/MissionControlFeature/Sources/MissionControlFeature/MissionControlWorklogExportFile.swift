import Foundation
import RuntimeCore

/// A written-to-disk snapshot of the runtime worklog, ready to hand off the device.
///
/// The worklog is the execution trace behind every receipt; ``WorklogStoring/exportAll()`` is its
/// byte-stable serialization. This is the surface that carries that snapshot somewhere it can be
/// diffed between runs — evals, operator report cards, a bug report — rather than only being read
/// in-process by Mission Control.
struct MissionControlWorklogExportFile: Identifiable, Equatable {
    let id = UUID()
    /// User-facing title for the share sheet and the sheet's own navigation bar.
    let title: String
    let url: URL
    let filename: String
    /// How many trace entries the file contains.
    let stepCount: Int
    /// Distinct workflows (correlation ids) represented.
    let workflowCount: Int
    let byteCount: Int
    /// A short digest of what was exported, shown instead of the raw JSON: the file is the artifact,
    /// the digest is what a person needs to confirm they are about to share the right trace.
    let summary: String
}

enum MissionControlWorklogExportError: Error, Equatable, LocalizedError {
    /// Nothing has been recorded yet, so there is no trace to hand off.
    case emptyTrace
    /// A workflow-scoped export whose correlation id has no entries in the snapshot.
    case workflowNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyTrace:
            return "There is no worklog trace to export yet. Run some governed work first."
        case let .workflowNotFound(correlationID):
            return "No worklog entries were found for workflow \(correlationID)."
        }
    }
}

enum MissionControlWorklogExportFileBuilder {
    /// Writes `steps` as a byte-stable JSON snapshot under `filename`.
    ///
    /// Re-encodes through ``WorklogExport/encode(_:)`` rather than passing the store's `Data` through
    /// verbatim, so a whole-trace export and a workflow-scoped slice of the same trace are produced by
    /// one encoder and stay comparable with each other.
    static func makeFile(
        steps: [WorkflowStepLog],
        title: String,
        filename: String,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> MissionControlWorklogExportFile {
        let data = try WorklogExport.encode(steps)
        let targetDirectory = directory ?? defaultExportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        // A trace carries proposal parameters (addresses, calldata) in plaintext; sweep abandoned
        // ones before writing a new one. Caller-supplied directories are left alone.
        if directory == nil {
            MissionControlExportSweep.pruneAbandonedExports(in: targetDirectory, fileManager: fileManager)
        }
        let url = targetDirectory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)
        let workflowCount = Set(steps.map { $0.correlationID ?? "(untracked):\($0.id.uuidString)" }).count
        return MissionControlWorklogExportFile(
            title: title,
            url: url,
            filename: filename,
            stepCount: steps.count,
            workflowCount: workflowCount,
            byteCount: data.count,
            summary: summary(for: steps, workflowCount: workflowCount)
        )
    }

    /// `worklog-trace-20260904-121500.json` — timestamped so successive exports don't overwrite each
    /// other and a diff between two of them is a diff between two known points in time.
    static func traceFilename(generatedAt: Date) -> String {
        "worklog-trace-\(timestampComponent(generatedAt)).json"
    }

    /// `worklog-corr-1-20260904-121500.json` for a single workflow's slice.
    static func workflowFilename(correlationID: String, generatedAt: Date) -> String {
        let scope = sanitizedFilenameComponent(correlationID, fallback: "workflow")
        return "worklog-\(scope)-\(timestampComponent(generatedAt)).json"
    }

    private static func summary(for steps: [WorkflowStepLog], workflowCount: Int) -> String {
        let timestamps = steps.map(\.timestamp)
        var summary = "\(steps.count) entr\(steps.count == 1 ? "y" : "ies") across \(workflowCount) workflow(s)"
        if let first = timestamps.min(), let last = timestamps.max() {
            let formatted = { (date: Date) in date.formatted(date: .abbreviated, time: .standard) }
            summary += first == last
                ? " • \(formatted(first))"
                : " • \(formatted(first)) → \(formatted(last))"
        }
        return summary
    }

    private static func timestampComponent(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func defaultExportDirectory(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("Auralis Worklog Exports", isDirectory: true)
    }

    private static func sanitizedFilenameComponent(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return collapsed.isEmpty ? fallback : collapsed
    }
}

extension MissionControlHomeModel {
    /// The durable worklog snapshot, decoded.
    ///
    /// Reads through ``WorklogStoring/exportAll()`` rather than `allSteps()` on purpose: exports must
    /// be built from the same self-contained, ordered serialization an eval run would consume, so what
    /// ships off-device is what the store says the trace is — not a live in-process view of it that
    /// happens to agree today.
    func exportedWorklogSteps() async throws -> [WorkflowStepLog] {
        let data = try await host.worklogStore.exportAll()
        return try JSONDecoder().decode([WorkflowStepLog].self, from: data)
    }

    /// Writes the whole runtime worklog to a shareable file. (P0.5-701/702)
    func exportWorklogTraceFile(directory: URL? = nil) async throws -> MissionControlWorklogExportFile {
        let steps = try await exportedWorklogSteps()
        guard !steps.isEmpty else { throw MissionControlWorklogExportError.emptyTrace }
        return try MissionControlWorklogExportFileBuilder.makeFile(
            steps: steps,
            title: "Runtime worklog trace",
            filename: MissionControlWorklogExportFileBuilder.traceFilename(generatedAt: referenceDate),
            directory: directory
        )
    }

    /// Writes one workflow's slice of the worklog to a shareable file — the trace behind a single
    /// session, for a bug report or a per-run report card.
    func exportWorklogTraceFile(
        forCorrelationID correlationID: String,
        directory: URL? = nil
    ) async throws -> MissionControlWorklogExportFile {
        let steps = try await exportedWorklogSteps().filter { $0.correlationID == correlationID }
        guard !steps.isEmpty else {
            throw MissionControlWorklogExportError.workflowNotFound(correlationID)
        }
        return try MissionControlWorklogExportFileBuilder.makeFile(
            steps: steps,
            title: "Workflow trace",
            filename: MissionControlWorklogExportFileBuilder.workflowFilename(
                correlationID: correlationID,
                generatedAt: referenceDate
            ),
            directory: directory
        )
    }
}

import ArtifactCore
import Foundation

struct MissionControlArtifactExportFile: Identifiable, Equatable {
    let id = UUID()
    let artifact: Artifact
    let title: String
    let url: URL
    let preview: String
    let filename: String
    let exportFormat: String
}

/// Housekeeping for the temp directories Mission Control writes shareable exports into.
///
/// Both an artifact export and a worklog trace are plaintext copies of governed data — artifact
/// content, and proposal parameters like addresses and calldata — written somewhere the share sheet
/// can read them. They were never removed, so every export a person ever opened accumulated until
/// the OS decided to reclaim the temp directory. Anything older than ``retentionWindow`` has outlived
/// the share that produced it.
enum MissionControlExportSweep {
    /// How long an export is assumed to still be in use.
    ///
    /// The file written by a given `makeFile` call is never at risk — pruning runs before the write.
    /// What this window bounds is *other* exports: a share sheet left open longer than an hour could
    /// have its file removed by a later export. That is the deliberate trade, because the alternative
    /// is plaintext governed data accumulating in the temp directory indefinitely.
    static let retentionWindow: TimeInterval = 60 * 60

    static func pruneAbandonedExports(
        in directory: URL,
        now: Date = .now,
        fileManager: FileManager = .default
    ) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for entry in entries {
            let modifiedAt = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            // An entry with no readable modification date is left in place: deleting a file we
            // cannot date is a worse failure than keeping one too long.
            guard let modifiedAt, now.timeIntervalSince(modifiedAt) > retentionWindow else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}

enum MissionControlArtifactExportFileBuilder {
    static func makeFile(
        for artifact: Artifact,
        payload: String,
        exportFormat: String,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> MissionControlArtifactExportFile {
        let filename = filename(for: artifact, exportFormat: exportFormat)
        let targetDirectory = directory ?? defaultExportDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        // Artifact content leaves the store in plaintext here, so abandoned exports are swept before
        // each new one rather than left for the OS to reclaim whenever it feels like it. Only the
        // directory this type owns is swept — a caller-supplied one is left alone.
        if directory == nil {
            MissionControlExportSweep.pruneAbandonedExports(in: targetDirectory, fileManager: fileManager)
        }
        let url = targetDirectory.appendingPathComponent(filename, isDirectory: false)
        try payload.write(to: url, atomically: true, encoding: .utf8)
        return MissionControlArtifactExportFile(
            artifact: artifact,
            title: artifact.title,
            url: url,
            preview: payload,
            filename: filename,
            exportFormat: exportFormat
        )
    }

    static func filename(for artifact: Artifact, exportFormat: String) -> String {
        let baseName = sanitizedFilenameComponent(artifact.title, fallback: artifact.type.rawValue)
        let idPrefix = artifact.id.uuidString.prefix(8).lowercased()
        return "\(baseName)-v\(artifact.version)-\(idPrefix).\(fileExtension(for: artifact.type, exportFormat: exportFormat))"
    }

    private static func defaultExportDirectory(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("Auralis Artifact Exports", isDirectory: true)
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

    private static func fileExtension(for type: ArtifactType, exportFormat: String) -> String {
        switch type {
        case .doc, .brief, .report, .planChecklist:
            return "md"
        case .jsonExport:
            return "json"
        case .codeFile:
            return sourceFileExtension(for: exportFormat)
        }
    }

    private static func sourceFileExtension(for exportFormat: String) -> String {
        switch exportFormat.lowercased() {
        case "swift": return "swift"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "python", "py": return "py"
        case "json": return "json"
        case "markdown", "md": return "md"
        case "html": return "html"
        case "css": return "css"
        case "source", "code", "text", "plain text", "txt": return "txt"
        default: return "txt"
        }
    }
}

extension MissionControlHomeModel {
    func exportFile(for artifact: Artifact, directory: URL? = nil) throws -> MissionControlArtifactExportFile {
        try MissionControlArtifactExportFileBuilder.makeFile(
            for: artifact,
            payload: exportPayload(for: artifact),
            exportFormat: exportFormatLabel(for: artifact),
            directory: directory
        )
    }
}

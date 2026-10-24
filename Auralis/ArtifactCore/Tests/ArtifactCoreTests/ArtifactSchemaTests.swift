@testable import ArtifactCore
import Foundation
import RuntimeCore
import Testing

@Suite("Artifact schema")
struct ArtifactSchemaTests {
    private func artifact(schemaVersion: Int = ArtifactSchema.currentVersion) -> Artifact {
        Artifact(
            id: UUID(),
            groupID: UUID(),
            version: 3,
            schemaVersion: schemaVersion,
            type: .report,
            title: "Watch report",
            creatorPlaybookID: nil,
            creatorOperatorID: "operator.onchain.watch",
            createdAt: Date(timeIntervalSince1970: 1_000),
            provenance: ArtifactProvenance(actor: .human),
            relatedReceiptIDs: [],
            approvalState: .draft,
            destination: nil,
            exportFormat: nil,
            content: "body"
        )
    }

    @Test("the current version is one this build reads")
    func currentVersionIsSupported() {
        #expect(ArtifactSchema.supports(ArtifactSchema.currentVersion))
        #expect(ArtifactSchema.supports(ArtifactSchema.legacyVersion))
        #expect(ArtifactSchema.supports(ArtifactSchema.currentVersion + 1) == false)
    }

    @Test("a new artifact carries the version this build writes")
    func newArtifactsCarryCurrentVersion() {
        #expect(artifact().schemaVersion == ArtifactSchema.currentVersion)
    }

    @Test("schemaVersion survives a JSON round trip")
    func schemaVersionRoundTrips() throws {
        let original = artifact()
        let decoded = try JSONDecoder().decode(Artifact.self, from: JSONEncoder().encode(original))

        #expect(decoded.schemaVersion == original.schemaVersion)
        #expect(decoded == original)
    }

    @Test("an artifact exported before the column decodes as the legacy version")
    func legacyExportDecodesAsLegacyVersion() throws {
        // An export produced by a build with no `schemaVersion` key. A required key here would turn
        // every previously exported archive into a decode error.
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(artifact())
        ) as? [String: Any] ?? [:]
        json.removeValue(forKey: "schemaVersion")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Artifact.self, from: legacyData)

        #expect(decoded.schemaVersion == ArtifactSchema.legacyVersion)
    }

    @Test("version is independent of the work product's revision number")
    func schemaVersionIsIndependentOfContentVersion() {
        let subject = artifact()

        #expect(subject.version == 3)
        #expect(subject.schemaVersion == 1)
    }

    /// A copy that changes nothing must equal its original.
    ///
    /// `Artifact`'s copy helpers call the memberwise initializer, where `schemaVersion` *defaults* to
    /// `currentVersion` — so a field omitted there is silently replaced rather than caught by the
    /// compiler. Asserting whole-value equality (rather than field-by-field) makes this a standing
    /// guard: any future property that the helpers forget to carry across fails this test too.
    @Test("a copy that changes nothing preserves every field, including the schema version")
    func copyPreservesEveryField() {
        // A shape written by a build that knew more than this one. Reachable in memory via JSON
        // decode, which records the stored version rather than failing closed the way the SwiftData
        // row does — and the value has to differ from `currentVersion` for the re-stamp to show.
        let original = artifact(schemaVersion: ArtifactSchema.currentVersion + 1)

        #expect(original.with(approvalState: original.approvalState) == original)
        #expect(original.with(approvalState: .approved).schemaVersion == original.schemaVersion)
    }

    /// Approving an older artifact must not rewrite the shape it was written under.
    @Test("lifecycle changes do not re-stamp the schema version")
    func lifecycleChangeKeepsSchemaVersion() {
        let original = artifact(schemaVersion: ArtifactSchema.currentVersion + 1)

        let exported = original.with(
            approvalState: .exported,
            destination: "Share sheet",
            exportFormat: "markdown"
        )
        #expect(exported.schemaVersion == original.schemaVersion)
        #expect(exported.approvalState == .exported)

        let linked = original.withRelatedReceipt(id: UUID())
        #expect(linked.schemaVersion == original.schemaVersion)
        #expect(linked.relatedReceiptIDs.count == 1)
    }

    @Test("declared field problems are reported, and absent fields are not invented")
    func declaredFieldProblems() {
        #expect(ArtifactSchema.problems(inDeclared: [:]).isEmpty)
        #expect(ArtifactSchema.problems(inDeclared: ["artifactType": "report"]).isEmpty)
        #expect(ArtifactSchema.problems(inDeclared: ["artifactType": "spreadsheet"]).count == 1)
        #expect(ArtifactSchema.problems(inDeclared: ["artifactTitle": " \n "]).count == 1)
        #expect(ArtifactSchema.problems(inDeclared: ["artifactTitle": "ok"]).isEmpty)
        #expect(
            ArtifactSchema.problems(
                inDeclared: ["artifactContent": String(repeating: "a", count: ArtifactSchema.maximumContentLength + 1)]
            ).count == 1
        )
    }

    @Test("every real artifact type is accepted", arguments: ArtifactType.allCases)
    func everyTypeIsAccepted(type: ArtifactType) {
        #expect(ArtifactSchema.problems(inDeclared: ["artifactType": type.rawValue]).isEmpty)
    }

    @Test("the field contract also applies to composed values, where they actually exist")
    func composedFieldProblems() {
        #expect(ArtifactSchema.problems(title: "Watch report", content: "body").isEmpty)
        // An empty body is legitimate — an operator that found nothing still writes a report.
        #expect(ArtifactSchema.problems(title: "Watch report", content: "").isEmpty)
        #expect(ArtifactSchema.problems(title: " \n ", content: "body").count == 1)
        #expect(
            ArtifactSchema.problems(
                title: "Watch report",
                content: String(repeating: "a", count: ArtifactSchema.maximumContentLength + 1)
            ).count == 1
        )
        // Exactly at the limit is inside it.
        #expect(
            ArtifactSchema.problems(
                title: "Watch report",
                content: String(repeating: "a", count: ArtifactSchema.maximumContentLength)
            ).isEmpty
        )
        #expect(ArtifactSchema.problems(title: "", content: String(repeating: "a", count: ArtifactSchema.maximumContentLength + 1)).count == 2)
    }
}

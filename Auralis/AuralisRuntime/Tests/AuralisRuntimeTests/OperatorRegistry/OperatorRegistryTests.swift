import Foundation
import AuralisRuntime
import Testing

@Suite("Operator manifest")
struct OperatorRegistryTests {
    @Test("All ten responsibility groups round-trip")
    func roundTrip() throws {
        let manifest = makeManifest()
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(OperatorManifest.self, from: encoded)

        #expect(decoded == manifest)
        #expect(decoded.definitionProblems.isEmpty)
    }

    @Test("Inference, memory, and scheduling are explicitly optional")
    func optionalRequirements() throws {
        let manifest = makeManifest()

        #expect(manifest.reasoning.usesInference == nil)
        #expect(manifest.context.permittedMemoryScopes == nil)
        #expect(manifest.events.schedulingRequirement == nil)
    }

    @Test("Registration stores declarations without creating runtime authority")
    func registrationIsNotAuthorization() async {
        let registry = OperatorManifestRegistry()
        let manifest = makeManifest()

        #expect(await registry.register(manifest))
        #expect(await registry.manifest(id: manifest.id) == manifest)
        #expect(await registry.all == [manifest])
    }

    @Test("Static manifests serialize no live permissions, context, progress, or commitments")
    func excludesLiveState() throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(makeManifest())) as? [String: Any]
        )

        for forbidden in ["currentPermissions", "currentContext", "progress", "activeCommitments"] {
            #expect(object[forbidden] == nil)
        }
    }

    private func makeManifest() -> OperatorManifest {
        OperatorManifest(
            id: "operator.example",
            operatorVersion: "1.0.0",
            identity: .init(
                title: "Example",
                purpose: "Prove the manifest contract",
                intendedOutcomes: ["A verified artifact"],
                principalScope: "requesting principal"
            ),
            context: .init(
                requiredFields: ["account"],
                permittedMemoryScopes: nil,
                dataScopes: ["profile"],
                maximumAgeSeconds: 60
            ),
            reasoning: .init(
                supportsPlanning: true,
                workflowIDs: ["example"],
                decisionBoundaries: ["human confirms writes"],
                usesInference: nil
            ),
            capabilities: .init(
                tool: ToolDefinition(
                    id: "operator.example",
                    title: "Example",
                    capability: .runPlugin,
                    impact: .readOnly,
                    requiresReceipt: true
                ),
                outputContracts: ["artifact.example"]
            ),
            authority: .init(
                requestedPermissions: ["plugin.run"],
                riskClassification: "read_only",
                confirmationBoundaries: ["writes"],
                revocationBehavior: "stop before next action"
            ),
            execution: .init(
                supportedCommitmentTypes: ["research"],
                lifecycleHooks: ["cancel"],
                cancellationBehavior: "cooperative",
                retryBehavior: "bounded",
                recoveryBehavior: "resume from evidence"
            ),
            events: .init(
                subscribedCategories: ["manual"],
                triggerIDs: [],
                idempotencyRequirement: "stable request ID",
                schedulingRequirement: nil
            ),
            records: .init(
                artifactTypes: ["brief"],
                requiresReceipt: true,
                evidenceRequirements: ["source provenance"]
            ),
            outcomes: .init(
                successCriteria: ["producedArtifact"],
                verificationRequirements: ["artifact exists"],
                failureSemantics: "commitment remains open",
                escalationSemantics: "request review"
            ),
            interface: .init(
                representations: ["mission-control-card"],
                interventionSurfaces: ["approval-inbox"],
                lifecycle: "stable",
                compatibility: "reject unsupported manifest versions"
            )
        )
    }
}

import AuralisContext
import AuralisFoundation
import AuralisPolicy
import AuralisReceipts
import AuralisRuntime
import Testing

@Test("Every root package product exposes a usable public API")
func productAPIsAreUsable() async throws {
    let principal = try #require(PrincipalID(rawValue: "mirenva.smoke-test"))
    #expect(principal.rawValue == "mirenva.smoke-test")

    let runtimeArtifact = ToolCallArtifact(
        toolID: "mirenva.smoke-test",
        summary: "Runtime API is available"
    )
    #expect(runtimeArtifact.toolID == "mirenva.smoke-test")

    let chain = ContextChainReference(id: "1", displayName: "Ethereum")
    #expect(chain.displayName == "Ethereum")

    let denial = PolicyGateResult(isAllowed: false, userMessage: "Denied by smoke-test policy")
    #expect(denial.isAllowed == false)

    let artifactStore = InMemoryArtifactStore()
    let artifact = await artifactStore.create(
        ArtifactDraft(
            type: .doc,
            title: "Mirenva smoke test",
            provenance: ArtifactProvenance(actor: ActorRef(kind: .human)),
            content: "Root package integration works."
        )
    )
    #expect(artifact.version == 1)
}

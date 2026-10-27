@testable import AuralisReceipts
import AuralisRuntime
import Testing

/// Covers the `ActorRef` → receipt-attribution bridges (P0.5-602): the coarse two-case `receiptActor`
/// and the full-fidelity `receiptActorDetail` that backs the structured receipt column.
struct ActorRefReceiptBridgeTests {
    @Test("model actor maps to full structured detail while keeping the coarse system mapping")
    func modelActorMapsToStructuredDetail() {
        let actor = ActorRef.model(
            identifier: "com.auralis.autopilot",
            inference: InferenceProvenance(locality: .remote, provider: "anthropic", modelClass: "opus")
        )

        // Coarse mapping is unchanged: every non-human actor is still `.system`.
        #expect(actor.receiptActor == .system)

        let detail = actor.receiptActorDetail
        #expect(detail.kind == ActorKind.model.rawValue)
        #expect(detail.identifier == "com.auralis.autopilot")
        #expect(detail.inferenceLocality == InferenceLocality.remote.rawValue)
        #expect(detail.inferenceProvider == "anthropic")
        #expect(detail.inferenceModelClass == "opus")
    }

    @Test("human actor stays user and carries no inference provenance")
    func humanActorMapsToUser() {
        #expect(ActorRef.human.receiptActor == .user)

        let detail = ActorRef.human.receiptActorDetail
        #expect(detail.kind == ActorKind.human.rawValue)
        // `ActorRef.human` is the local-user identity, so the bridge carries that identifier through.
        // This previously asserted `nil` and had been failing unnoticed: the suite aborted on an
        // `ActorRef` precondition before this test could report.
        #expect(detail.identifier == "local-user")
        // The part that matters for privacy: a human actor never carries inference provenance.
        #expect(detail.inferenceLocality == nil)
        #expect(detail.inferenceProvider == nil)
    }
}

import Foundation
@testable import RuntimeCore
import Testing

@Suite("Outcome and performance primitives")
struct OutcomeSpecTests {
    @Test("OutcomeSpec preserves structured and prose criteria")
    func outcomeSpecRoundTripsThroughJSON() throws {
        let id = UUID()
        let original = OutcomeSpec(
            id: id,
            summary: "A reviewable artifact exists.",
            criteria: [.producedArtifact, .completedWithin(seconds: 30)],
            proseCriteria: ["The result is useful to a person."]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OutcomeSpec.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == id)
    }

    @Test("Legacy prose remains descriptive instead of becoming executable")
    func legacyOutcomeSpecDecodesWithoutInventingCriteria() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "summary": "Legacy intent",
          "successCriteria": ["Looks correct"]
        }
        """

        let decoded = try JSONDecoder().decode(OutcomeSpec.self, from: Data(json.utf8))

        #expect(decoded.criteria.isEmpty)
        #expect(decoded.proseCriteria == ["Looks correct"])
    }

    @Test("PerformanceRecord preserves its complete portable contract")
    func performanceRecordRoundTripsThroughJSON() throws {
        let original = PerformanceRecord(
            id: UUID(),
            sessionID: UUID(),
            outcomeID: UUID(),
            succeeded: true,
            durationSeconds: 1.25,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PerformanceRecord.self, from: data)

        #expect(decoded == original)
    }
}

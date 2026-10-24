@testable import RuntimeCore
import Testing

@Suite("ActionImpactClass")
struct ActionImpactClassTests {
    @Test(arguments: [
        (ActionImpactClass.readOnly, false, false),
        (ActionImpactClass.reversibleWrite, true, false),
        (ActionImpactClass.externalImpact, true, true),
        (ActionImpactClass.highRisk, true, true)
    ])
    func derivedRequirements(_ testCase: (kind: ActionImpactClass, receipt: Bool, confirm: Bool)) {
        #expect(testCase.kind.requiresReceipt == testCase.receipt)
        #expect(testCase.kind.requiresConfirmation == testCase.confirm)
    }

    @Test
    func rawValuesRoundTrip() {
        for kind in ActionImpactClass.allCases {
            #expect(ActionImpactClass(rawValue: kind.rawValue) == kind)
        }
    }
}

import AuralisPrimaryModels
import CapabilitiesCore
import Foundation
@testable import AccountsCore
@testable import RuntimeCore
import Testing

/// Hex and numeric parameters must be ASCII, not merely "Unicode-numeric".
///
/// `Character.isHexDigit` and `isNumber` both accept digit variants no Ethereum tooling does —
/// fullwidth `０`–`９`, Arabic-Indic `١٢٣`. A 40-character fullwidth "address" therefore satisfied
/// the input schema, and because it carries no cased letters EIP-55 called it `.unchecksummed`, which
/// is a *warning*: a confusable address cleared both governance gates and reached the high-risk
/// signing path. ``ENSNameFormatCheck`` already refuses this class for names; these pin the same rule
/// for every hex and quantity field.
@Suite("Confusable parameter rejection")
struct ConfusableParameterTests {
    private static let fullwidthHex = String(repeating: "０", count: 40)
    private static let asciiAddress = "0x" + String(repeating: "a", count: 40)

    @Test("the address schema field refuses non-ASCII digits")
    func addressFieldRefusesFullwidthDigits() {
        let schema = ToolSchema(fields: [ToolSchemaField(name: "address", kind: .address)])
        let problems = schema.validationProblems(against: ["address": "0x" + Self.fullwidthHex])
        #expect(problems.count == 1)
        #expect(problems[0].contains("40-hex address"))
        // The ASCII form is unaffected.
        #expect(schema.validationProblems(against: ["address": Self.asciiAddress]).isEmpty)
    }

    @Test(
        "every hex-shaped field refuses non-ASCII digits",
        arguments: [
            (ToolSchemaField.Kind.hexData, "0x" + String(repeating: "０", count: 8)),
            (ToolSchemaField.Kind.transactionHash, "0x" + String(repeating: "０", count: 64)),
            (ToolSchemaField.Kind.signature, "0x" + String(repeating: "０", count: 8)),
            (ToolSchemaField.Kind.chainID, "0x" + String(repeating: "０", count: 2)),
            (ToolSchemaField.Kind.unsignedQuantity, "0x" + String(repeating: "０", count: 2))
        ]
    )
    func hexFieldsRefuseFullwidthDigits(kind: ToolSchemaField.Kind, value: String) {
        #expect(kind.validationProblem(for: value) != nil)
    }

    @Test("unsigned quantities refuse non-ASCII decimal digits")
    func unsignedQuantityRefusesArabicIndicDigits() {
        #expect(ToolSchemaField.Kind.unsignedQuantity.validationProblem(for: "١٢٣") != nil)
        #expect(ToolSchemaField.Kind.unsignedQuantity.validationProblem(for: "123") == nil)
    }

    /// Defence in depth: the deterministic check must refuse it too, not just the schema.
    ///
    /// The check reads through `AuralisEthereumAddress`, which shared the same permissive test. With
    /// both layers ASCII-restricted, a confusable address fails the check outright instead of passing
    /// with a warning.
    @Test("AddressFormatCheck fails a fullwidth-digit address rather than warning")
    func addressCheckFailsFullwidthDigits() async {
        #expect(AuralisEthereumAddress("0x" + Self.fullwidthHex) == nil)
        #expect(AuralisEthereumAddress.checksumState(of: "0x" + Self.fullwidthHex) == .malformed)

        let result = await AddressFormatCheck().evaluate(
            ActionProposal(
                actor: .human,
                intent: "send",
                capability: .draftTransaction,
                impact: .highRisk,
                parameters: ["address": "0x" + Self.fullwidthHex]
            )
        )
        #expect(result.severity == .failure)
        #expect(result.passed == false)
    }

    @Test("a legitimate ASCII address still passes the check")
    func asciiAddressStillPasses() async {
        let result = await AddressFormatCheck().evaluate(
            ActionProposal(
                actor: .human,
                intent: "send",
                capability: .draftTransaction,
                impact: .highRisk,
                parameters: ["address": Self.asciiAddress]
            )
        )
        #expect(result.passed)
    }
}

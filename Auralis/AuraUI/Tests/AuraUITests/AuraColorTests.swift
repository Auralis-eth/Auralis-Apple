import SwiftUI
import Testing
@testable import AuraUI

@Suite("Aura colors")
struct AuraColorTests {
    @Test("Parses shorthand hex")
    func parsesShorthandHex() {
        let components = Color.rgbaComponents(from: "#0F8")

        #expect(components?.red == 0)
        #expect(components?.green == 255)
        #expect(components?.blue == 136)
        #expect(components?.alpha == 255)
    }

    @Test("Parses alpha hex")
    func parsesAlphaHex() {
        let components = Color.rgbaComponents(from: "7751A980")

        #expect(components?.red == 119)
        #expect(components?.green == 81)
        #expect(components?.blue == 169)
        #expect(components?.alpha == 128)
    }

    @Test("Rejects invalid hex")
    func rejectsInvalidHex() {
        #expect(Color.rgbaComponents(from: "not-a-color") == nil)
    }
}

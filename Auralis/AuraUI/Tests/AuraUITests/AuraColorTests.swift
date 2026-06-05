import SwiftUI
import Testing
@testable import AuraUI

@Suite("Aura colors")
struct AuraColorTests {
    @Test("Parses shorthand hex")
    func parsesShorthandHex() {
        let components = Color.rgbaComponents(from: "#0F8")

        #expect(try #require(components).red == 0)
        #expect(try #require(components).green == 255)
        #expect(try #require(components).blue == 136)
        #expect(try #require(components).alpha == 255)
    }

    @Test("Parses alpha hex")
    func parsesAlphaHex() {
        let components = Color.rgbaComponents(from: "7751A980")

        #expect(try #require(components).red == 119)
        #expect(try #require(components).green == 81)
        #expect(try #require(components).blue == 169)
        #expect(try #require(components).alpha == 128)
    }

    @Test("Rejects invalid hex")
    func rejectsInvalidHex() {
        #expect(Color.rgbaComponents(from: "not-a-color") == nil)
    }
}

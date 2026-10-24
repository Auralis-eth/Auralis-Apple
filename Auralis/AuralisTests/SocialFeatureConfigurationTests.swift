@testable import Auralis
import Testing

@Suite("Social feature configuration")
struct SocialFeatureConfigurationTests {
    @Test("relay gate is closed by default")
    func relayGateDefaultsClosed() {
        let configuration = SocialFeatureConfiguration(infoDictionary: [:])
        #expect(!configuration.relayEnabled)
    }

    @Test("relay gate accepts explicit enabled values")
    func relayGateParsesEnabledValues() {
        for value in ["YES", "true", "1", "enabled"] {
            let configuration = SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": value])
            #expect(configuration.relayEnabled)
        }
    }

    @Test("relay gate rejects placeholders and disabled values")
    func relayGateRejectsDisabledValues() {
        for value in ["NO", "false", "0", "$(AURALIS_SOCIAL_RELAY_ENABLED)", ""] {
            let configuration = SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": value])
            #expect(!configuration.relayEnabled)
        }
    }
}

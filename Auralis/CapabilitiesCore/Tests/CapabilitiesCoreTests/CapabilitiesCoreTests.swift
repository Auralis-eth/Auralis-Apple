import CapabilitiesCore
import Testing

struct CapabilitiesCoreTests {
    @Test("registry covers every canonical capability")
    func registryCoversEveryCapability() {
        #expect(CapabilityRegistry.descriptors.count == CapabilityID.allCases.count)

        for id in CapabilityID.allCases {
            let descriptor = CapabilityRegistry.descriptor(for: id)
            #expect(descriptor.id == id)
            #expect(descriptor.title.isEmpty == false)
            #expect(descriptor.summary.isEmpty == false)
        }
    }

    @Test("legacy mapping preserves canonical raw values")
    func legacyMappingPreservesCanonicalRawValues() {
        #expect(CapabilityID.legacy("sign_message") == .signMessage)
        #expect(CapabilityID.legacy("audio_playback") == .audioPlayback)
        #expect(CapabilityID.legacy("unknown_capability") == nil)
    }
}

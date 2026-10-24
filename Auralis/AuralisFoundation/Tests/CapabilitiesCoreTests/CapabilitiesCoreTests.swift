import CapabilitiesCore
import Foundation
import Testing

struct CapabilitiesCoreTests {
    @Test("registry covers every canonical capability")
    func registryCoversEveryCapability() {
        #expect(CapabilityRegistry.descriptors.count == CapabilityID.allCases.count)

        for id in CapabilityID.allCases {
            #expect(CapabilityRegistry.descriptors[id] != nil)
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

    @Test("raw values are frozen wire format")
    func rawValuesAreFrozenWireFormat() {
        #expect(CapabilityID.signMessage.rawValue == "sign_message")
        #expect(CapabilityID.approveSpending.rawValue == "approve_spending")
        #expect(CapabilityID.draftTransaction.rawValue == "draft_transaction")
        #expect(CapabilityID.runPlugin.rawValue == "run_plugin")
        #expect(CapabilityID.playlistManagement.rawValue == "playlist_management")
        #expect(CapabilityID.autoOrganization.rawValue == "auto_organization")
        #expect(CapabilityID.musicLibraryClassification.rawValue == "music_library_classification")
        #expect(CapabilityID.metadataOverride.rawValue == "metadata_override")
        #expect(CapabilityID.backgroundMusicTask.rawValue == "background_music_task")
        #expect(CapabilityID.musicExport.rawValue == "music_export")
        #expect(CapabilityID.playbackQueue.rawValue == "playback_queue")
        #expect(CapabilityID.audioPlayback.rawValue == "audio_playback")
        #expect(CapabilityID.allCases.count == 12)
    }

    @Test("decoding accepts the emitted raw value and nothing wider", arguments: CapabilityID.allCases)
    func decodingAcceptsOnlyRawValues(capability: CapabilityID) throws {
        let encoded = try JSONEncoder().encode(capability)
        #expect(String(bytes: encoded, encoding: .utf8) == "\"\(capability.rawValue)\"")
        #expect(try JSONDecoder().decode(CapabilityID.self, from: encoded) == capability)

        let caseName = String(describing: capability)
        if caseName != capability.rawValue {
            let camelCase = Data("\"\(caseName)\"".utf8)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(CapabilityID.self, from: camelCase)
            }
        }
    }
}

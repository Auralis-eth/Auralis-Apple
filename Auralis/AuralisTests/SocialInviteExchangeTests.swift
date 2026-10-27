@testable import Auralis
import Foundation
import AuralisOperators
import Testing

@Suite("Social invite coding")
struct SocialInviteCodingTests {
    private func sampleInvite() -> SocialInvite {
        SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
    }

    @Test("Encode then decode round-trips the invite")
    func roundTrips() throws {
        let invite = sampleInvite()
        let decoded = try SocialInviteCoding.decode(try SocialInviteCoding.encode(invite))
        #expect(decoded == invite)
    }

    @Test("Encoded form is scheme-prefixed and whitespace-tolerant on decode")
    func schemePrefixedAndTrimmed() throws {
        let invite = sampleInvite()
        let code = try SocialInviteCoding.encode(invite)
        #expect(code.hasPrefix(SocialInviteCoding.scheme + ":"))
        #expect(try SocialInviteCoding.decode("  \n" + code + "\n ") == invite)
    }

    @Test("Garbage, wrong-scheme, and non-invite payloads fail closed")
    func garbageFailsClosed() {
        #expect(throws: SocialInviteCodingError.malformed) { _ = try SocialInviteCoding.decode("hello world") }
        #expect(throws: SocialInviteCodingError.malformed) { _ = try SocialInviteCoding.decode("aura-social:not-base64!!") }
        #expect(throws: SocialInviteCodingError.malformed) {
            _ = try SocialInviteCoding.decode("aura-social:" + Data(#"{"nope":1}"#.utf8).base64EncodedString())
        }
    }

    /// An invite that decodes cleanly but claims an expiry no minter could produce is refused.
    ///
    /// `SocialInviteMint` clamps TTL to a week, but `decode` asserted nothing and the join path only
    /// checked `!invite.isExpired()`. A hand-crafted QR carrying `expiresAt` in the year 3000 was
    /// therefore accepted verbatim and saved: expiry pruning would never reclaim it, so the session's
    /// durable log was bounded only by the per-session envelope ceiling.
    @Test("An invite claiming an implausible expiry is refused")
    func implausibleExpiryIsRefused() throws {
        let forged = SocialInvite(
            sessionID: UUID(),
            relayTopic: SocialInviteMint.randomHex(byteCount: SocialInviteMint.topicByteCount),
            encryptedSessionKey: SocialSessionKey.generateBase64Encoded(),
            inviterParticipantID: "mallory",
            expiresAt: Date(timeIntervalSince1970: 32_503_680_000),  // year 3000
            nonce: SocialInviteMint.randomHex(byteCount: SocialInviteMint.nonceByteCount)
        )

        #expect(throws: SocialInviteCodingError.implausibleInvite) {
            _ = try SocialInviteCoding.decode(try SocialInviteCoding.encode(forged))
        }
    }

    /// The shape screen applies at decode time, not only on the optional wallet-signing path — so an
    /// invite with arbitrary topic/nonce contents cannot be persisted and subscribed just because its
    /// holder never runs a join challenge.
    @Test("An invite whose topic or nonce is not minted hex is refused", arguments: [
        "not-a-topic",
        "",
        String(repeating: "A", count: 64),   // uppercase: not what randomHex emits
        String(repeating: "f", count: 63)    // one nibble short
    ])
    func unmintedFieldsAreRefused(topic: String) throws {
        let forged = SocialInvite(
            sessionID: UUID(),
            relayTopic: topic,
            encryptedSessionKey: SocialSessionKey.generateBase64Encoded(),
            inviterParticipantID: "mallory",
            expiresAt: Date().addingTimeInterval(3_600),
            nonce: SocialInviteMint.randomHex(byteCount: SocialInviteMint.nonceByteCount)
        )

        #expect(throws: SocialInviteCodingError.implausibleInvite) {
            _ = try SocialInviteCoding.decode(try SocialInviteCoding.encode(forged))
        }
    }

    /// An invite minted at the default TTL must keep decoding — the bound allows a day of clock skew
    /// between host and joiner, and must not reject the ordinary case.
    @Test("A freshly minted invite at the default TTL still decodes")
    func defaultTTLInviteStillDecodes() throws {
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")

        #expect(try SocialInviteCoding.decode(try SocialInviteCoding.encode(invite)) == invite)
    }
}

@Suite("Social relay assembly")
struct SocialRelayAssemblyTests {
    private func makeAssembly(relayEnabled: Bool, store: SocialEventLogStore) -> SocialRelayAssembly {
        let composition = SocialRelayComposition(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": relayEnabled]),
            eventLogStore: store
        )
        return SocialRelayAssembly(
            composition: composition,
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(transport: FakeAssemblyTransport(), inboundSource: SilentInboundSource())
            }
        )
    }

    @Test("Disabled relay hosts nothing and starts no runtime")
    func disabledHostsNothing() async throws {
        let store = SocialEventLogStore()
        let assembly = makeAssembly(relayEnabled: false, store: store)

        #expect(try await assembly.hostSession(sessionID: UUID(), inviterParticipantID: "alice") == nil)
        #expect(try await assembly.joinSession(invite: SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "bob")) == false)
        #expect(await assembly.activeSessionIDs().isEmpty)
        #expect(await store.allInvites().isEmpty)
    }

    @Test("Enabled host mints an invite, persists it, and starts one runtime (idempotent)")
    func enabledHostsAndStarts() async throws {
        let store = SocialEventLogStore()
        let assembly = makeAssembly(relayEnabled: true, store: store)
        let sessionID = UUID()

        let invite = try #require(try await assembly.hostSession(sessionID: sessionID, inviterParticipantID: "alice"))
        #expect(invite.sessionID == sessionID)
        #expect(await store.allInvites().map(\.sessionID) == [sessionID])
        #expect(await assembly.activeSessionIDs() == [sessionID])

        // Re-hosting returns the *same* invite rather than minting over the live one.
        //
        // Asserting only the runtime count used to pass while the session was silently bricked: a second
        // mint produced a fresh topic and a fresh session key, saved them over the stored invite, and hit
        // the "already running" early return — leaving the coordinator publishing to the new topic sealed
        // with the old key and quarantining its own inbound traffic as a foreign session.
        let reHosted = try #require(
            try await assembly.hostSession(sessionID: sessionID, inviterParticipantID: "alice")
        )
        #expect(reHosted.relayTopic == invite.relayTopic)
        #expect(reHosted.encryptedSessionKey == invite.encryptedSessionKey)
        #expect(reHosted.nonce == invite.nonce)
        #expect(await assembly.activeSessionIDs() == [sessionID])
        #expect(await store.allInvites().map(\.relayTopic) == [invite.relayTopic])
    }

    /// A second invite claiming a session id this device already holds is refused.
    ///
    /// `saveInvite` replaces the stored invite for its session id *and* adds the inviter to that
    /// session's durable owner-bootstrap anchor set. Without this guard, anyone who photographed a QR
    /// for session S could mint their own invite reusing that session id, get the victim to scan it, and
    /// rewrite the stored relay topic and session key while installing themselves as an owner anchor for
    /// a session they never hosted.
    @Test("A conflicting invite for a known session id is refused and changes nothing")
    func conflictingInviteForKnownSessionIsRefused() async throws {
        let store = SocialEventLogStore()
        let assembly = makeAssembly(relayEnabled: true, store: store)
        let sessionID = UUID()
        let genuine = SocialInviteMint.mint(sessionID: sessionID, inviterParticipantID: "alice")
        #expect(try await assembly.joinSession(invite: genuine) == true)

        let attacker = SocialInviteMint.mint(sessionID: sessionID, inviterParticipantID: "mallory")

        await #expect(throws: SocialJoinError.conflictingInvite) {
            try await assembly.joinSession(invite: attacker)
        }

        let stored = await store.allInvites()
        #expect(stored.count == 1)
        #expect(stored.first?.relayTopic == genuine.relayTopic)
        #expect(stored.first?.encryptedSessionKey == genuine.encryptedSessionKey)
        #expect(stored.first?.inviterParticipantID == "alice")
        #expect(await assembly.activeSessionIDs() == [sessionID])
    }

    /// Re-scanning the *same* invite is a no-op, not a second join and not a conflict.
    @Test("Re-joining with an identical invite succeeds without duplicating state")
    func identicalRejoinIsIdempotent() async throws {
        let store = SocialEventLogStore()
        let assembly = makeAssembly(relayEnabled: true, store: store)
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")

        #expect(try await assembly.joinSession(invite: invite) == true)
        #expect(try await assembly.joinSession(invite: invite) == true)

        #expect(await store.allInvites().count == 1)
        #expect(await assembly.activeSessionIDs() == [invite.sessionID])
    }

    @Test("Join from an encoded code persists the invite and starts the session")
    func joinFromCode() async throws {
        let store = SocialEventLogStore()
        let assembly = makeAssembly(relayEnabled: true, store: store)
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "carol")

        #expect(try await assembly.joinSession(code: SocialInviteCoding.encode(invite)) == true)
        #expect(await store.allInvites().map(\.sessionID) == [invite.sessionID])
        #expect(await assembly.activeSessionIDs() == [invite.sessionID])
    }

    @Test("Join with a malformed code fails closed before touching the relay")
    func joinMalformedCode() async {
        let assembly = makeAssembly(relayEnabled: true, store: SocialEventLogStore())
        await #expect(throws: SocialInviteCodingError.malformed) {
            _ = try await assembly.joinSession(code: "garbage")
        }
        #expect(await assembly.activeSessionIDs().isEmpty)
    }

    @Test("Relay failure rolls back invite and runtime ownership")
    func relayFailureRollsBackJoin() async {
        let store = SocialEventLogStore()
        let assembly = SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
                eventLogStore: store
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(
                    transport: FailingAssemblyTransport(),
                    inboundSource: SilentInboundSource()
                )
            }
        )
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")

        await #expect(throws: RelayTestError.offline) {
            _ = try await assembly.joinSession(invite: invite)
        }
        #expect(await store.allInvites().isEmpty)
        #expect(await assembly.activeSessionIDs().isEmpty)
    }

    /// The rollback must not delete an invite it did not create.
    ///
    /// Nothing restarts runtimes at launch, so re-scanning the QR for a session joined in an earlier
    /// launch reaches `startRuntime` with the invite already durably stored. Rolling that back on an
    /// offline retry destroyed the session's relay topic and encrypted session key — material
    /// `hostSession` cannot re-mint — so one failed resume permanently lost the session.
    @Test("A failed resume leaves an already-stored invite intact")
    func failedResumeKeepsPreexistingInvite() async {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
        // Stand in for "joined in an earlier launch": the invite is durably held, no runtime is live.
        await store.saveInvite(invite)

        let assembly = SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
                eventLogStore: store
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(
                    transport: FailingAssemblyTransport(),
                    inboundSource: SilentInboundSource()
                )
            }
        )

        await #expect(throws: RelayTestError.offline) {
            _ = try await assembly.joinSession(invite: invite)
        }

        let stored = await store.allInvites()
        #expect(stored.count == 1)
        #expect(stored.first?.relayTopic == invite.relayTopic)
        #expect(stored.first?.encryptedSessionKey == invite.encryptedSessionKey)
        #expect(await assembly.activeSessionIDs().isEmpty)
    }

    @Test("Stopping a session forgets its runtime")
    func stopForgetsRuntime() async throws {
        let assembly = makeAssembly(relayEnabled: true, store: SocialEventLogStore())
        let sessionID = UUID()
        _ = try await assembly.hostSession(sessionID: sessionID, inviterParticipantID: "alice")

        await assembly.stopSession(sessionID: sessionID)
        #expect(await assembly.activeSessionIDs().isEmpty)
    }
}

private enum RelayTestError: Error {
    case offline
}

private struct FailingAssemblyTransport: SocialRelayTransporting {
    func subscribe(topic: String) async throws { throw RelayTestError.offline }
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws {
        throw RelayTestError.offline
    }
}

@MainActor
@Suite("Social invite exchange model")
struct SocialInviteExchangeModelTests {
    private func makeAssembly(relayEnabled: Bool, store: SocialEventLogStore) -> SocialRelayAssembly {
        SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": relayEnabled]),
                eventLogStore: store
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(transport: FakeAssemblyTransport(), inboundSource: SilentInboundSource())
            }
        )
    }

    @Test("Host produces a shareable code when enabled")
    func hostProducesCode() async throws {
        let model = SocialInviteExchangeModel(assembly: makeAssembly(relayEnabled: true, store: SocialEventLogStore()), participantID: "alice")
        await model.host(sessionID: UUID())

        // `try #require`, not `try? #require`: swallowing the requirement turned a missing code into
        // `code == nil` and left the assertion below to fail for the wrong stated reason.
        let code = try #require(model.shareableCode)
        #expect(code.hasPrefix(SocialInviteCoding.scheme + ":"))
        if case .hosting = model.state {} else { Issue.record("expected hosting state, got \(model.state)") }
    }

    @Test("Host reports disabled when the relay flag is off")
    func hostDisabled() async {
        let model = SocialInviteExchangeModel(assembly: makeAssembly(relayEnabled: false, store: SocialEventLogStore()), participantID: "alice")
        await model.host(sessionID: UUID())
        #expect(model.state == .disabled)
        #expect(model.shareableCode == nil)
    }

    @Test("A code hosted on one device imports and joins on another")
    func hostThenImportElsewhere() async {
        let hostModel = SocialInviteExchangeModel(assembly: makeAssembly(relayEnabled: true, store: SocialEventLogStore()), participantID: "alice")
        await hostModel.host(sessionID: UUID())
        let code = hostModel.shareableCode ?? ""

        // A second, independent device (separate store/assembly) imports the shared code.
        let joinStore = SocialEventLogStore()
        let joinModel = SocialInviteExchangeModel(assembly: makeAssembly(relayEnabled: true, store: joinStore), participantID: "bob")
        await joinModel.importInvite(code: code)

        if case let .joined(sessionID, verificationNotice) = joinModel.state {
            #expect(await joinStore.allInvites().map(\.sessionID) == [sessionID])
            // No verifier is wired here, so the ownership proof is never attempted and there is
            // nothing to warn about.
            #expect(verificationNotice == nil)
        } else {
            Issue.record("expected joined state, got \(joinModel.state)")
        }
    }

    @Test("Importing garbage fails without joining")
    func importGarbage() async {
        let model = SocialInviteExchangeModel(assembly: makeAssembly(relayEnabled: true, store: SocialEventLogStore()), participantID: "alice")
        await model.importInvite(code: "not-an-invite")
        if case .failed = model.state {} else { Issue.record("expected failed state, got \(model.state)") }
    }
}

private actor FakeAssemblyTransport: SocialRelayTransporting {
    func subscribe(topic: String) async throws { }
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws { }
}

private struct SilentInboundSource: SocialRelayInboundStreaming {
    func inboundMessages() async -> AsyncStream<SocialRelayInboundMessage> {
        AsyncStream { $0.finish() }
    }
}

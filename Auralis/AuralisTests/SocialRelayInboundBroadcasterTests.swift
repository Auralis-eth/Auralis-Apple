@testable import Auralis
import Foundation
import Testing
import WalletConnectorKit

/// The relay socket's event stream is a single `AsyncStream`, and `AsyncStream` is **unicast** — each
/// yielded element reaches exactly one iterator.
///
/// Handing that stream to every session meant two live sessions split the inbound traffic between their
/// pumps instead of each seeing all of it, and since a pump discards anything not on its bound topic,
/// roughly half of each session's messages vanished non-deterministically with no retry and no record.
/// ``SocialRelayInboundBroadcaster`` consumes the socket once and re-yields to every subscriber; this
/// suite exists because that fan-out is pure routing logic, and the original bug survived precisely
/// because no test could reach it.
@Suite("Social relay inbound broadcaster")
struct SocialRelayInboundBroadcasterTests {
    private func makeBroadcaster() -> (SocialRelayInboundBroadcaster, AsyncStream<WalletConnectRelayEvent>.Continuation) {
        var upstream: AsyncStream<WalletConnectRelayEvent>.Continuation!
        let stream = AsyncStream<WalletConnectRelayEvent> { upstream = $0 }
        let broadcaster = SocialRelayInboundBroadcaster(events: { stream })
        return (broadcaster, upstream)
    }

    private func subscription(topic: String, message: String) -> WalletConnectRelayEvent {
        .subscription(topic: topic, message: message, tag: nil)
    }

    /// The defect this type was written for: both sessions must see **every** message, not a split.
    @Test("two subscribers each receive every message rather than splitting the stream")
    func twoSubscribersEachReceiveEveryMessage() async throws {
        let (broadcaster, upstream) = makeBroadcaster()
        var firstIterator = await broadcaster.subscribe().makeAsyncIterator()
        var secondIterator = await broadcaster.subscribe().makeAsyncIterator()

        upstream.yield(subscription(topic: "topic-a", message: "m1"))
        upstream.yield(subscription(topic: "topic-b", message: "m2"))

        let firstA = await firstIterator.next()
        let secondA = await secondIterator.next()
        #expect(firstA?.message == "m1")
        #expect(secondA?.message == "m1")

        let firstB = await firstIterator.next()
        let secondB = await secondIterator.next()
        #expect(firstB?.message == "m2")
        #expect(secondB?.message == "m2")
        #expect(firstB?.topic == "topic-b")
        #expect(secondB?.topic == "topic-b")
    }

    /// Registration is ordered: `subscribe()` returns only once the subscriber is installed, so a
    /// message yielded immediately afterwards cannot slip past it. A fire-and-forget registration made
    /// `SocialRelaySessionRuntime`'s "inbound-first so a message arriving during subscribe is not
    /// missed" ordering unenforceable, and the relay's mailbox replay is delivered exactly once.
    @Test("a message yielded right after subscribe is still delivered")
    func registrationIsOrderedWithRespectToDelivery() async throws {
        let (broadcaster, upstream) = makeBroadcaster()
        var iterator = await broadcaster.subscribe().makeAsyncIterator()

        upstream.yield(subscription(topic: "topic-a", message: "first"))

        #expect(await iterator.next()?.message == "first")
    }

    /// Non-message socket events (connect/disconnect and friends) are routing noise, not inbound
    /// payloads, and must not surface to a session's pump.
    @Test("non-subscription relay events are dropped")
    func nonSubscriptionEventsAreDropped() async throws {
        let (broadcaster, upstream) = makeBroadcaster()
        var iterator = await broadcaster.subscribe().makeAsyncIterator()

        upstream.yield(.socketStatusChanged(.connected))
        upstream.yield(subscription(topic: "topic-a", message: "payload"))

        // The only element to arrive is the subscription payload; `.connected` was skipped rather than
        // mapped to an empty message.
        #expect(await iterator.next()?.message == "payload")
    }

    /// Finishing upstream must terminate every subscriber's stream, so a pump's `for await` exits
    /// instead of hanging forever on a dead socket.
    @Test("finishing upstream finishes every subscriber")
    func finishingUpstreamFinishesSubscribers() async throws {
        let (broadcaster, upstream) = makeBroadcaster()
        var iterator = await broadcaster.subscribe().makeAsyncIterator()

        upstream.yield(subscription(topic: "topic-a", message: "only"))
        upstream.finish()

        #expect(await iterator.next()?.message == "only")
        #expect(await iterator.next() == nil)
    }

    /// A session that ends must stop consuming, without disturbing the sessions still running — the
    /// per-subscriber teardown that `onTermination` drives.
    @Test("a remaining subscriber keeps receiving after another is torn down")
    func teardownOfOneSubscriberDoesNotAffectAnother() async throws {
        let (broadcaster, upstream) = makeBroadcaster()
        let survivor = await broadcaster.subscribe()
        var survivorIterator = survivor.makeAsyncIterator()

        // Subscribe, consume nothing, and let the stream deallocate so `onTermination` fires.
        do {
            _ = await broadcaster.subscribe()
        }

        upstream.yield(subscription(topic: "topic-a", message: "after-teardown"))

        #expect(await survivorIterator.next()?.message == "after-teardown")
    }
}

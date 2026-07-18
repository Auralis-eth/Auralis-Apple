import AuraPlayMediaCore
import Foundation
import Testing

struct SeekCoalescerTests {
    actor SeekRecorder {
        private(set) var performedTargets: [TimeInterval] = []
        private var gate: CheckedContinuation<Void, Never>?
        var holdsFirstSeek = false

        func setHoldsFirstSeek(_ holds: Bool) {
            holdsFirstSeek = holds
        }

        func perform(_ target: TimeInterval) async {
            performedTargets.append(target)
            if holdsFirstSeek, performedTargets.count == 1 {
                await withCheckedContinuation { continuation in
                    gate = continuation
                }
            }
        }

        func releaseGate() {
            gate?.resume()
            gate = nil
        }
    }

    @Test("A single request performs one seek at the requested target")
    func singleRequestSeeks() async {
        let coalescer = SeekCoalescer()
        let recorder = SeekRecorder()

        await coalescer.requestSeek(to: 42) { target, _ in
            await recorder.perform(target)
        }

        #expect(await recorder.performedTargets == [42])
    }

    @Test("Targets are clamped to zero")
    func negativeTargetClamps() async {
        let coalescer = SeekCoalescer()
        let recorder = SeekRecorder()

        await coalescer.requestSeek(to: -5) { target, _ in
            await recorder.perform(target)
        }

        #expect(await recorder.performedTargets == [0])
    }

    @Test("Rapid requests while a seek is in flight coalesce to the latest target")
    func rapidRequestsCoalesce() async {
        let coalescer = SeekCoalescer()
        let recorder = SeekRecorder()
        await recorder.setHoldsFirstSeek(true)

        let firstSeek = Task {
            await coalescer.requestSeek(to: 10) { target, _ in
                await recorder.perform(target)
            }
        }

        // Wait until the first seek is actually in flight.
        while await recorder.performedTargets.isEmpty {
            await Task.yield()
        }

        // These arrive while the first seek is still running; only the last
        // target may be performed afterward.
        await coalescer.requestSeek(to: 20) { target, _ in
            await recorder.perform(target)
        }
        await coalescer.requestSeek(to: 30) { target, _ in
            await recorder.perform(target)
        }
        await coalescer.requestSeek(to: 40) { target, _ in
            await recorder.perform(target)
        }

        await recorder.releaseGate()
        await firstSeek.value

        let targets = await recorder.performedTargets
        #expect(targets.first == 10)
        #expect(targets.last == 40)
        #expect(!targets.contains(20))
        #expect(!targets.contains(30))
    }
}

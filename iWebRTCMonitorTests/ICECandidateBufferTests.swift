import Testing
import WebRTC
@testable import iWebRTCMonitor

@MainActor
struct ICECandidateBufferTests {
    @Test
    func candidateBeforeReadinessIsBuffered() {
        var buffer = IcePeerState<String>()

        #expect(!buffer.isReady)
        #expect(buffer.receive("first") == nil)
        #expect(!buffer.isReady)
        #expect(buffer.markReady() == ["first"])
    }

    @Test
    func multipleCandidatesRetainArrivalOrder() {
        var buffer = IcePeerState<Int>()
        // Include a duplicate: buffering must not deduplicate candidates.
        let candidates = [3, 1, 3, 2]

        for candidate in candidates {
            #expect(buffer.receive(candidate) == nil)
        }

        #expect(buffer.markReady() == candidates)
    }

    @Test
    func successfulReadinessDrainsCandidatesExactlyOnce() {
        var buffer = IcePeerState<String>()
        #expect(buffer.receive("first") == nil)
        #expect(buffer.receive("second") == nil)

        #expect(buffer.markReady() == ["first", "second"])
        #expect(buffer.isReady)
        #expect(buffer.markReady() == [])
        #expect(buffer.receive("third") == "third")
        #expect(buffer.markReady() == [])
    }

    @Test
    func readinessBeforeCandidatesMakesLaterCandidatesImmediatelyEligible() {
        var buffer = IcePeerState<Int>()

        #expect(buffer.markReady() == [])
        #expect(buffer.isReady)
        #expect(buffer.receive(1) == 1)
        #expect(buffer.receive(2) == 2)
        #expect(buffer.markReady() == [])
    }

    @Test
    func repeatedReadinessDoesNotReplayCandidates() {
        var buffer = IcePeerState<Int>()
        #expect(buffer.receive(1) == nil)
        #expect(buffer.markReady() == [1])

        for _ in 0..<3 {
            #expect(buffer.markReady() == [])
            #expect(buffer.isReady)
        }
    }

    @Test
    func independentBuffersDoNotShareState() {
        var first = IcePeerState<String>()
        var second = IcePeerState<String>()
        #expect(first.receive("first") == nil)
        #expect(second.receive("second") == nil)

        #expect(first.markReady() == ["first"])
        #expect(!second.isReady)
        #expect(second.receive("third") == nil)
        #expect(first.receive("fourth") == "fourth")
        #expect(second.markReady() == ["second", "third"])
        #expect(first.markReady() == [])
    }

    @Test
    func copiedBuffersMutateIndependently() {
        var original = IcePeerState<Int>()
        #expect(original.receive(1) == nil)
        var copy = original

        #expect(copy.receive(2) == nil)
        #expect(copy.markReady() == [1, 2])
        #expect(!original.isReady)
        #expect(original.receive(3) == nil)
        #expect(original.markReady() == [1, 3])
        #expect(copy.markReady() == [])
    }

    @Test
    func bufferedSignalingCandidatesPreserveFieldsThroughWebRTCConversion() {
        var buffer = IcePeerState<RTCIceCandidateMessage>()
        let messages = [
            RTCIceCandidateMessage(sdp: "candidate:1 1 UDP 2122260223 192.0.2.1 5000 typ host", sdpMLineIndex: 0, sdpMid: "audio"),
            RTCIceCandidateMessage(sdp: "candidate:2 1 UDP 2122260222 192.0.2.2 5001 typ host", sdpMLineIndex: 1, sdpMid: nil)
        ]
        for message in messages {
            #expect(buffer.receive(message) == nil)
        }

        let submitted = buffer.markReady().map { RTCIceCandidate.from($0).toMessage() }
        #expect(submitted.map(\.sdp) == messages.map(\.sdp))
        #expect(submitted.map(\.sdpMLineIndex) == messages.map(\.sdpMLineIndex))
        #expect(submitted.map(\.sdpMid) == messages.map(\.sdpMid))
        #expect(buffer.markReady().isEmpty)
    }

}

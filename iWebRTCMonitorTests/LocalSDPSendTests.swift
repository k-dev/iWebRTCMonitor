import Foundation
import Testing
import WebRTC
@testable import iWebRTCMonitor

private final class SDPValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func store(_ value: Value) { lock.withLock { self.value = value } }
    func load() -> Value { lock.withLock { value } }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LocalSDPSendTests {
    @MainActor
    private struct Fixture {
        let server: LocalWebSocketServer
        let manager: SessionManager
        let client: WebRTCClient
        let connection: WebSocketConnection
        func stop() { manager.stop(); server.stop() }
    }

    private func registeredClient(_ manager: SessionManager) async throws -> WebRTCClient {
        let value = SDPValue<WebRTCClient?>(nil)
        await manager.checkedContinuationSnapshot { value.store($0?.webRTCClients[.monitor]) }
        return try #require(value.load())
    }

    private func connection(_ manager: SessionManager) async throws -> WebSocketConnection {
        let value = SDPValue<WebSocketConnection?>(nil)
        await manager.checkedContinuationSnapshot { value.store($0?.signalingClient.connection) }
        return try #require(value.load())
    }

    private func fixture() async throws -> Fixture {
        let server = try LocalWebSocketServer()
        do {
            let address = try await server.start()
            let manager = SessionManager(serverAddress: address, roomID: "sdp-tests",
                                         role: .viewer, peerID: "same-peer")
            try manager.start()
            try await server.waitForConnections(1)
            return Fixture(server: server, manager: manager,
                           client: try await registeredClient(manager),
                           connection: try await connection(manager))
        } catch { server.stop(); throw error }
    }

    private func description(_ type: RTCSdpType) -> RTCSessionDescription {
        RTCSessionDescription(type: type, sdp: "local-sdp-regression-payload")
    }

    private func onSessionQueue(_ manager: SessionManager,
                                _ action: @escaping (SessionManager) throws -> Void) async throws {
        let error = SDPValue<Error?>(nil)
        await manager.checkedContinuationSnapshot { session in
            do { try action(try #require(session)) }
            catch let caught { error.store(caught) }
        }
        if let error = error.load() { throw error }
    }

    private func expectObsoleteConnection(_ action: () async throws -> Void) async {
        do { try await action(); Issue.record("Obsolete connection must be rejected") }
        catch SignalingError.obsoleteConnection { }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    private func received(_ f: Fixture, on connection: WebSocketConnection) async throws -> [String] {
        let marker = "sdp-fence-\(UUID())"
        try await onSessionQueue(f.manager) { try $0.signalingClient.send(marker, using: connection) }
        return try await f.server.messages(through: marker)
    }

    @Test(arguments: [RTCSdpType.offer, .answer])
    func staleDescriptionAfterReplacement(type: RTCSdpType) async throws {
        let f = try await fixture()
        defer { f.stop() }
        let pendingDescription = description(type)
        await f.manager.checkedContinuationSnapshot { $0?.registerWebRTCClient(for: .monitor) }
        #expect(try await registeredClient(f.manager) !== f.client)
        try await onSessionQueue(f.manager) {
            $0.handleLocalSDP(pendingDescription, error: nil, type: type, to: .monitor, from: f.client)
        }
        #expect(try await received(f, on: f.connection).isEmpty)
    }

    @Test
    func completionAfterPeerRemoval() async throws {
        let f = try await fixture()
        defer { f.stop() }
        let pendingDescription = description(.offer)
        await f.manager.checkedContinuationSnapshot { $0?.cleanupPeer(.monitor) }
        try await onSessionQueue(f.manager) {
            $0.handleLocalSDP(pendingDescription, error: nil, type: .offer, to: .monitor, from: f.client)
        }
        #expect(try await received(f, on: f.connection).isEmpty)
    }

    @Test
    func completionAfterStopRestartWithReusedPeer() async throws {
        let f = try await fixture()
        defer { f.stop() }
        let pendingDescription = description(.answer)
        f.manager.stop()
        try f.manager.start()
        try await f.server.waitForConnections(2)
        await f.manager.checkedContinuationSnapshot { $0?.registerWebRTCClient(for: .monitor) }
        let replacement = try await connection(f.manager)
        #expect(replacement !== f.connection)
        try await onSessionQueue(f.manager) {
            $0.handleLocalSDP(pendingDescription, error: nil, type: .answer, to: .monitor, from: f.client)
        }
        #expect(try await received(f, on: replacement).isEmpty)
    }

    @Test(arguments: [RTCSdpType.offer, .answer])
    func validDescriptionHasOneRemoteReceipt(type: RTCSdpType) async throws {
        let f = try await fixture()
        defer { f.stop() }
        // Admission occurs on the owner queue; server receipt is awaited below.
        try await onSessionQueue(f.manager) {
            $0.handleLocalSDP(description(type), error: nil, type: type, to: .monitor, from: f.client)
        }
        // A separate wire-order fence establishes receipt and allows exact counting.
        let messages = try await received(f, on: f.connection)
        try #require(messages.count == 1)
        let object = try #require(JSONSerialization.jsonObject(with: Data(messages[0].utf8)) as? [String: Any])
        #expect(object["type"] as? String == (type == .offer ? "offer" : "answer"))
        #expect(object["from"] as? String == "same-peer")
        let payload = try #require(object["payload"] as? [String: Any])
        #expect(payload["sdp"] as? String == description(type).sdp)
        #expect(payload["type"] as? String == (type == .offer ? "offer" : "answer"))
    }

    @Test(arguments: [RTCSdpType.offer, .answer])
    func registeredClientSendsSDPThroughReplacementConnection(type: RTCSdpType) async throws {
        let f = try await fixture()
        defer { f.stop() }
        // Drain queued retirement before connecting the replacement.
        try await onSessionQueue(f.manager) { $0.signalingClient.disconnect() }
        try await onSessionQueue(f.manager) { try $0.signalingClient.connect() }
        try await f.server.waitForConnections(2)
        let replacement = try await connection(f.manager)
        #expect(replacement !== f.connection)
        #expect(try await registeredClient(f.manager) === f.client)
        let sdp = description(type)
        try await onSessionQueue(f.manager) {
            $0.handleLocalSDP(sdp, error: nil, type: type, to: .monitor, from: f.client)
        }
        let messages = try await received(f, on: replacement)
        try #require(messages.count == 1)
        let object = try #require(JSONSerialization.jsonObject(with: Data(messages[0].utf8)) as? [String: Any])
        #expect(object["type"] as? String == type.toString())
        #expect(object["from"] as? String == "same-peer")
        let payload = try #require(object["payload"] as? [String: Any])
        #expect(payload["type"] as? String == type.toString())
        #expect(payload["sdp"] as? String == sdp.sdp)
    }

    @Test
    func retiredConnectionRejectsDirectSend() async throws {
        let f = try await fixture()
        defer { f.stop() }
        try await onSessionQueue(f.manager) { $0.signalingClient.disconnect() }
        try await onSessionQueue(f.manager) { try $0.signalingClient.connect() }
        try await f.server.waitForConnections(2)
        let replacement = try await connection(f.manager)
        await expectObsoleteConnection {
            try await onSessionQueue(f.manager) { try $0.signalingClient.send("obsolete", using: f.connection) }
        }
        #expect(try await received(f, on: replacement).isEmpty)
    }
}

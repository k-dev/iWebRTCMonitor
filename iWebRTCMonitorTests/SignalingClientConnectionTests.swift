import Foundation
import Testing
import XCTest
@testable import iWebRTCMonitor

@MainActor
struct SignalingClientConnectionTests {
    @Test
    func delayedHandshakeDoesNotReportConnectedUntilTransportOpens() async throws {
        let server = try LocalWebSocketServer(holdsHandshake: true)
        defer { server.stop() }
        let address = try await server.start()
        let client = SignalingClient(serverAddress: address, roomID: "delayed-start",
                                     role: .monitor, peerID: nil, queue: .main)
        defer { client.disconnect() }
        let prematureOpen = XCTestExpectation(description: "No open before WebSocket upgrade")
        prematureOpen.isInverted = true
        client.onConnected = { _ in prematureOpen.fulfill() }
        try client.connect()
        let pending = try #require(client.connection)
        let result = await XCTWaiter.fulfillment(of: [prematureOpen], timeout: 0.3)
        #expect(result == .completed)

        let opened = XCTestExpectation(description: "Open after delayed WebSocket upgrade")
        client.onConnected = { _ in opened.fulfill() }
        server.resumeHandshakes()
        let resumed = await XCTWaiter.fulfillment(of: [opened], timeout: 5)
        #expect(resumed == .completed)
        #expect(client.connection === pending, "Availability must resume the same connection")
    }

    @Test
    func disconnectDuringPendingHandshakeSuppressesLateOpen() async throws {
        let server = try LocalWebSocketServer(holdsHandshake: true)
        defer { server.stop() }
        let address = try await server.start()
        let client = SignalingClient(serverAddress: address, roomID: "cancel-start",
                                     role: .monitor, peerID: nil, queue: .main)
        let unexpectedOpen = XCTestExpectation(description: "Stopped connection must not open")
        unexpectedOpen.isInverted = true
        client.onConnected = { _ in unexpectedOpen.fulfill() }
        try client.connect()
        client.disconnect()
        server.resumeHandshakes()
        let result = await XCTWaiter.fulfillment(of: [unexpectedOpen], timeout: 0.3)
        #expect(result == .completed)
        #expect(client.connection == nil)
    }

    private func drainCallbacks() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func makeClient() -> SignalingClient {
        SignalingClient(serverAddress: "ws://127.0.0.1:1", roomID: "connection-tests",
                        role: .viewer, peerID: "same-peer", queue: .main)
    }

    @Test
    func delegateCallbacksAndSendUseOwnerQueue() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let queue = DispatchQueue(label: "signaling-owner-test")
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        let client = SignalingClient(serverAddress: address, roomID: "connection-tests",
                                     role: .viewer, peerID: "same-peer", queue: queue)
        defer { queue.sync { client.disconnect() } }
        var received: [String] = []
        try queue.sync {
            client.onConnected = { _ in
                #expect(DispatchQueue.getSpecific(key: key) == true)
            }
            client.onMessage = { _, text in
                #expect(DispatchQueue.getSpecific(key: key) == true)
                received.append(text)
            }
            client.onDisconnected = { _, _ in
                #expect(DispatchQueue.getSpecific(key: key) == true)
            }
            try client.connect()
        }
        try await server.waitForConnections(1)
        let connection = try queue.sync { try #require(client.connection) }
        await client.connection(connection, didReceive: .string("incoming"))
        queue.sync { #expect(received == ["incoming"]) }

        let marker = "owner-queue-\(UUID())"
        try queue.sync { try client.send(marker, using: connection) }
        // Admission above is distinct from server receipt below.
        #expect(try await server.messages(through: marker).isEmpty)

        // A termination originating outside the owner queue is marshalled too.
        client.connectionDidClose(connection, with: URLError(.cancelled))
        queue.sync { #expect(client.connection == nil) }
        connection.close()
    }

    @Test
    func activeDelegateMessagesUseLatestCallbackAndRejectOldConnection() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let client = SignalingClient(serverAddress: address, roomID: "connection-tests",
                                     role: .viewer, peerID: "same-peer", queue: .main)
        defer {
            client.disconnect()
            client.onMessage = nil
        }
        var received: [String] = []
        client.onMessage = { received.append("original: \($1)") }
        try client.connect()
        try await server.waitForConnections(1)
        let original = try #require(client.connection)
        await client.connection(original, didReceive: .string("first"))
        await drainCallbacks()
        client.onMessage = { received.append("latest: \($1)") }
        await client.connection(original, didReceive: .data(Data("second".utf8)))
        await drainCallbacks()
        #expect(received == ["original: first", "latest: second"])

        client.disconnect()
        await drainCallbacks()
        try client.connect()
        try await server.waitForConnections(2)
        let replacement = try #require(client.connection)
        #expect(replacement !== original)
        await client.connection(original, didReceive: .string("stale"))
        await drainCallbacks()
        #expect(client.connection === replacement)
        #expect(received == ["original: first", "latest: second"])
        await client.connection(replacement, didReceive: .string("third"))
        await drainCallbacks()
        #expect(received == ["original: first", "latest: second", "latest: third"])
    }

    @Test
    func disconnectedClientRejectsDelegateMessages() async throws {
        let client = makeClient()
        let inactive = WebSocketConnection(url: try #require(URL(string: "ws://127.0.0.1:1")))
        defer {
            inactive.close()
            client.onMessage = nil
        }
        var received: [String] = []
        client.onMessage = { received.append("original: \($1)") }
        await client.connection(inactive, didReceive: .string("first"))
        await drainCallbacks()
        client.onMessage = { received.append("latest: \($1)") }
        await client.connection(inactive, didReceive: .data(Data("second".utf8)))
        await drainCallbacks()
        #expect(received.isEmpty)
        #expect(!client.isConnected)
    }

    @Test
    func inactiveConnectionCannotNotifyOrRetireReplacementConnection() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let client = SignalingClient(serverAddress: address, roomID: "connection-tests",
                                     role: .viewer, peerID: "same-peer", queue: .main)
        defer { client.disconnect() }
        var disconnected: [String] = []
        client.onDisconnected = { _, _ in disconnected.append("A") }
        try client.connect()
        try await server.waitForConnections(1)
        let original = try #require(client.connection)
        client.disconnect()
        await drainCallbacks()
        #expect(client.connection == nil)
        #expect(disconnected == ["A"])

        client.onDisconnected = { _, _ in disconnected.append("B") }
        try client.connect()
        try await server.waitForConnections(2)
        await drainCallbacks()
        let replacement = try #require(client.connection)
        #expect(replacement !== original)
        client.onConnected = { _ in Issue.record("Inactive connection must not notify connected") }
        client.connectionDidOpen(original)
        client.connectionDidClose(original, with: URLError(.cancelled))
        await drainCallbacks()
        #expect(client.connection === replacement)
        #expect(client.isConnected)
        #expect(disconnected == ["A"])

        client.disconnect()
        client.disconnect()
        await drainCallbacks()
        #expect(client.connection == nil)
        #expect(disconnected == ["A", "B"])
    }

    @Test
    func duplicateConnectPreservesActiveConnectionAndUsesLatestCallbacks() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let client = SignalingClient(serverAddress: address, roomID: "connection-tests",
                                     role: .viewer, peerID: "same-peer", queue: .main)
        defer { client.disconnect() }
        var disconnected: [String] = []
        var connectedCount = 0
        client.onConnected = { _ in connectedCount += 1 }
        client.onDisconnected = { _, _ in disconnected.append("original") }
        try client.connect()
        try await server.waitForConnections(1)
        await drainCallbacks()
        let original = try #require(client.connection)
        #expect(connectedCount == 1)

        client.onDisconnected = { _, _ in disconnected.append("replacement") }
        do {
            try client.connect()
            Issue.record("Duplicate connect must throw")
        } catch SignalingError.alreadyConnected {
            #expect(client.connection === original)
        }
        await drainCallbacks()
        #expect(connectedCount == 1)
        client.disconnect()
        await drainCallbacks()
        #expect(disconnected == ["replacement"])
        #expect(client.connection == nil)
    }

    @Test
    func disconnectRetiresConnectionBeforeReturningOnOwnerQueue() throws {
        let client = makeClient()
        defer { client.disconnect() }
        try client.connect()
        client.disconnect()
        // This assertion must run before queued delegate events can execute.
        #expect(client.connection == nil, "Synchronous shutdown must retire the connection before returning")
    }
}

import Foundation
import Testing
import WebRTC
@testable import iWebRTCMonitor

private final class LifecycleValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func store(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SessionLifecycleTests {
    private func makeSession(serverAddress: String = "ws://127.0.0.1:1") -> SessionManager {
        // Viewer initialization avoids starting camera capture. No socket is opened.
        SessionManager(serverAddress: serverAddress, roomID: "lifecycle-tests",
                       role: .viewer, peerID: "same-peer")
    }

    private func hasNoPeers(_ manager: SessionManager) async -> Bool {
        let result = LifecycleValue(false)
        await manager.checkedContinuationSnapshot { session in
            result.store(session?.webRTCClients.isEmpty == true)
        }
        return result.load()
    }

    private func connection(_ manager: SessionManager) async throws -> WebSocketConnection {
        let value = LifecycleValue<WebSocketConnection?>(nil)
        await manager.checkedContinuationSnapshot { value.store($0?.signalingClient.connection) }
        return try #require(value.load())
    }

    @Test
    func stopRemovesExistingPeers() async {
        let manager = makeSession()
        defer { manager.stop() }

        let attached = LifecycleValue(false)
        await manager.checkedContinuationSnapshot { session in
            attached.store(session?.webRTCClients[.monitor] != nil)
        }
        #expect(attached.load())
        manager.stop()
        #expect(await hasNoPeers(manager))
    }

    @Test
    func signalingAfterStopDoesNotCreatePeer() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let manager = makeSession(serverAddress: address)
        defer { manager.stop() }
        try manager.start()
        try await server.waitForConnections(1)
        let original = try await connection(manager)
        manager.stop()

        await manager.signalingClient.connection(
            original, didReceive: .string(#"{"type":"monitorConnected"}"#)
        )
        #expect(await hasNoPeers(manager), "Disconnected connection must not recreate a peer")
    }

    @Test
    func signalingQueuedBeforeStopDoesNotCreatePeerAfterCleanup() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let manager = makeSession(serverAddress: address)
        defer { manager.stop() }
        try manager.start()
        try await server.waitForConnections(1)
        let client = manager.signalingClient
        let original = try await connection(manager)
        let enqueued = DispatchSemaphore(value: 0)
        let accepted = LifecycleValue(false)
        let emptyImmediatelyAfterStop = LifecycleValue(false)

        await manager.checkedContinuationSnapshot { session in
            // The real connection queues delegate delivery while A is active.
            // Hold the session queue until delegate delivery has enqueued its work.
            Task.detached {
                await client.connection(original, didReceive: .string(#"{"type":"monitorConnected"}"#))
                enqueued.signal()
            }
            guard enqueued.wait(timeout: .now() + 5) == .success else { return }
            accepted.store(client.connection === original)
            session?.stop()
            emptyImmediatelyAfterStop.store(session?.webRTCClients.isEmpty == true)
        }

        try #require(accepted.load(), "Delegate delivery must enqueue while A is active")
        #expect(emptyImmediatelyAfterStop.load())
        #expect(await hasNoPeers(manager), "Queued delegate delivery must not recreate a peer")
    }

    private func monitorClient(_ manager: SessionManager) async -> WebRTCClient? {
        let result = LifecycleValue<WebRTCClient?>(nil)
        await manager.checkedContinuationSnapshot { session in
            result.store(session?.webRTCClients[.monitor])
        }
        return result.load()
    }

    @Test
    func restartRejectsQueuedAndLateDelegateMessagesFromPreviousConnection() async throws {
        let server = try LocalWebSocketServer()
        defer { server.stop() }
        let address = try await server.start()
        let manager = makeSession(serverAddress: address)
        defer { manager.stop() }
        try manager.start()
        try await server.waitForConnections(1)
        let client = manager.signalingClient
        let original = try await connection(manager)
        let enqueued = DispatchSemaphore(value: 0)
        let accepted = LifecycleValue(false)
        let restarted = LifecycleValue(false)
        let restartError = LifecycleValue<Error?>(nil)

        await manager.checkedContinuationSnapshot { session in
            Task.detached {
                await client.connection(original, didReceive: .string(#"{"type":"monitorConnected"}"#))
                enqueued.signal()
            }
            guard enqueued.wait(timeout: .now() + 5) == .success,
                  let session else { return }
            accepted.store(client.connection === original)
            session.stop()
            session.stop()
            do {
                try session.start()
                restarted.store(true)
            } catch {
                restartError.store(error)
            }
        }

        try #require(accepted.load(), "Delegate delivery must enqueue while A is active")
        try #require(restarted.load(), "Synchronous restart must complete; error: \(String(describing: restartError.load()))")
        try await server.waitForConnections(2)
        let replacement = try await connection(manager)
        #expect(replacement !== original)
        #expect(manager.signalingClient === client)
        #expect(await hasNoPeers(manager), "A's queued delivery must not create B's peer")

        await client.connection(replacement, didReceive: .string(#"{"type":"monitorConnected"}"#))
        let peerB = try #require(await monitorClient(manager))
        await client.connection(original, didReceive: .string(#"{"type":"monitorConnected"}"#))
        #expect(await monitorClient(manager) === peerB, "Late A delivery must not replace B's peer")
        await client.connection(replacement, didReceive: .string(#"{"type":"monitorConnected"}"#))
        let replacementB = try #require(await monitorClient(manager))
        #expect(replacementB !== peerB)
        manager.stop()
        manager.stop()
        #expect(await hasNoPeers(manager))
    }
}

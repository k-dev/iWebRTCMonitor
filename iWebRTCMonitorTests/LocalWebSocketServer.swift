import Foundation
import Network
import Testing
import XCTest

/// Keeps real client sockets open while tests control delegate delivery.
final class LocalWebSocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local-websocket-test-server")
    private let listener: NWListener
    private var holdsHandshake: Bool
    // Accessed only on queue.
    private var connections: [NWConnection] = []
    private var readyCount = 0
    private var waiters: [Int: XCTestExpectation] = [:]
    private var messages: [String] = []
    private var messageWaiters: [String: XCTestExpectation] = [:]

    init(holdsHandshake: Bool = false) throws {
        self.holdsHandshake = holdsHandshake
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> String {
        let ready = XCTestExpectation(description: "WebSocket listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections.append(connection)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self, case .ready = state else { return }
                self.readyCount += 1
                let satisfied = self.waiters.keys.filter { $0 <= self.readyCount }
                for count in satisfied { self.waiters.removeValue(forKey: count)?.fulfill() }
                self.receive(connection)
            }
            if !self.holdsHandshake { connection.start(queue: self.queue) }
        }
        listener.start(queue: queue)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 5)
        try #require(result == .completed, "Local WebSocket listener did not become ready")
        let port = try #require(listener.port)
        return "ws://127.0.0.1:\(port.rawValue)"
    }

    func waitForConnections(_ count: Int) async throws {
        let ready = XCTestExpectation(description: "\(count) WebSocket handshakes complete")
        queue.async {
            if self.readyCount >= count { ready.fulfill() }
            else { self.waiters[count] = ready }
        }
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 5)
        try #require(result == .completed, "Client WebSocket handshake did not complete")
    }

    func stop() {
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
            listener.cancel()
        }
    }

    /// Allows tests to keep TCP accepted but the WebSocket upgrade pending.
    func resumeHandshakes() {
        queue.async {
            guard self.holdsHandshake else { return }
            self.holdsHandshake = false
            self.connections.forEach { $0.start(queue: self.queue) }
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let text = String(data: data, encoding: .utf8) {
                self.messages.append(text)
                self.messageWaiters.removeValue(forKey: text)?.fulfill()
            }
            if error == nil { self.receive(connection) }
        }
    }

    /// A marker on the same socket follows earlier admitted frames in wire order.
    /// Waiting for receipt is separate from awaiting socket-send completion.
    func messages(through marker: String) async throws -> [String] {
        let received = XCTestExpectation(description: "Receive marker \(marker)")
        queue.async {
            if self.messages.contains(marker) { received.fulfill() }
            else { self.messageWaiters[marker] = received }
        }
        let result = await XCTWaiter.fulfillment(of: [received], timeout: 5)
        try #require(result == .completed, "Server did not receive the marker")
        return queue.sync { Array(messages.prefix { $0 != marker }) }
    }
}

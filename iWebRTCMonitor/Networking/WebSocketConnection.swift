//
//  WebSocketConnection.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 09.05.2026.
//

import Foundation

/// Wraps one URL session WebSocket task.
///
/// `SignalingClient` creates, starts, and stops using this object. The receive loop
/// runs in a detached task. Its delegate receives open, message, and close
/// callbacks. A send completion reports local socket completion only; it does
/// not report receipt by the remote peer.
final class WebSocketConnection: @unchecked Sendable {
    
    /// Receives lifecycle and message events from one connection.
    protocol Delegate: AnyObject {
        func connectionDidOpen(_ connection: WebSocketConnection) -> Void
        func connection(_ connection: WebSocketConnection, didReceive message: URLSessionWebSocketTask.Message) async -> Void
        func connectionDidClose(_ connection: WebSocketConnection, with error: Error?) -> Void
    }
    
    private let transport: URLSession
    private let socket: URLSessionWebSocketTask
    private let sessionHandler: WebSocketSessionHandler
    
    let id = UUID()
    weak var delegate: Delegate?

    init(url: URL, delegate: Delegate? = nil) {
        self.delegate = delegate
        // The first local-network request can precede the user's permission
        // decision. Keep it pending so approval resumes the same session.
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        self.sessionHandler = WebSocketSessionHandler()
        self.transport = URLSession(configuration: configuration, delegate: sessionHandler, delegateQueue: nil)
        self.socket = transport.webSocketTask(with: url)
    }

    func start() {
        sessionHandler.onSessionOpen =  { [weak self] _, _, _ in
            if let self {
                self.delegate?.connectionDidOpen(self)
            }
        }

        socket.resume()
        Task.detached { await self.receiveLoop() }
    }

    /// Synchronously submits to the native socket. Completion is transport-level,
    /// not acknowledgement of remote receipt.
    func enqueueSend(_ message: URLSessionWebSocketTask.Message,
                     completion: @escaping @Sendable (Error?) -> Void) {
        socket.send(message, completionHandler: completion)
    }

    func close() {
        // Retire this identity before cancellation can complete the receive.
        // The owner suppresses duplicate/stale termination notifications.
        delegate?.connectionDidClose(self, with: nil)
        cancelTransport()
    }

    private func cancelTransport() {
        socket.cancel(with: .goingAway, reason: nil)
        transport.invalidateAndCancel()
    }

    private func receiveLoop() async {
        defer { cancelTransport() }
        do {
            while true {
                let message = try await socket.receive()
                
                await delegate?.connection(self, didReceive: message)
            }
        } catch {
            delegate?.connectionDidClose(self, with: error)
        }
    }
}

final class WebSocketSessionHandler: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    
    var onSessionOpen: ((URLSession, URLSessionWebSocketTask, String?) -> Void)?
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onSessionOpen?(session, webSocketTask, `protocol`)
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        Log(category: .signaling, level: .status, "Signaling waiting for network access or connectivity")
    }
}

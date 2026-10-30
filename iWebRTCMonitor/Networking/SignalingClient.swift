//
//  SignalingClient.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 09.05.2026.
//

import Foundation

/// Identifies the local endpoint role in a signaling room.
enum Role: String, Codable {
    case monitor
    case viewer
}

/// Reports invalid signaling lifecycle or routing operations.
enum SignalingError: Error {
    case alreadyConnected
    case invalidURL
    case notConnected
    case incorrectEnvelopeFrom
    case obsoleteConnection
}

extension Logger.Category {
    static let signaling = Self(rawValue: "signaling", logLevel: nil, prefix: "SIGNALING")
}

/// Owns the active signaling connection for one session.
///
/// `SessionManager` creates and releases this object. Its owner must call its
/// state-changing methods on the queue supplied at initialization. Connection
/// callbacks return to that queue and reject callbacks from old connections.
final class SignalingClient: @unchecked Sendable {

    private let queue: DispatchQueue
    private(set) var connection: WebSocketConnection?

    var isConnected: Bool { connection != nil }

    let serverAddress: String
    let roomID: String
    let role: Role
    let peerID: String?

    var onMessage: ((WebSocketConnection, String) -> Void)?
    var onConnected: ((WebSocketConnection) -> Void)?
    var onDisconnected: ((WebSocketConnection, Error?) -> Void)?

    init(serverAddress: String, roomID: String, role: Role, peerID: String?, queue: DispatchQueue) {
        self.queue = queue
        self.serverAddress = serverAddress
        self.roomID = roomID
        self.role = role
        self.peerID = peerID
    }

    /// Creates and starts the next connection. The caller owns queue serialization.
    func connect() throws {
        guard self.connection == nil else {
            throw SignalingError.alreadyConnected
        }
        guard let serverURL = URL(string: serverAddress) else {
            throw SignalingError.invalidURL
        }

        var url = serverURL
            .appending(path: "signal")
            .appending(path: roomID)
            .appending(path: role.rawValue)
        if let peerID {
            url = url.appending(path: peerID)
        }
        guard let socketURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?.url else {
            throw SignalingError.invalidURL
        }

        connection = WebSocketConnection(url: socketURL, delegate: self)
        connection?.start()
    }

    /// Sends only through the connection that the caller selected on the owner queue.
    func send(_ message: String, using aConnection: WebSocketConnection) throws {
        guard connection === aConnection else {
            throw SignalingError.obsoleteConnection
        }

        aConnection.enqueueSend(.string(message)) { error in
            if let error {
                Log(category: .signaling, level: .warning, "Signaling send failed", error)
            }
        }
    }

    /// Stops using the current connection before its receive loop can report completion.
    func disconnect() {
        connection?.close()
        if let conn = connection {
            connection = nil
            onDisconnected?(conn, nil)
        }
    }
}

extension SignalingClient: WebSocketConnection.Delegate {

    func connectionDidOpen(_ connection: WebSocketConnection) {
        queue.async { [weak self] in
            guard self?.connection === connection else {
                return
            }
            self?.onConnected?(connection)
        }
    }

    func connection(_ connection: WebSocketConnection, didReceive message: URLSessionWebSocketTask.Message) async {
        queue.async { [weak self] in
            guard self?.connection === connection else {
                return
            }

            switch message {
            case .string(let text): self?.onMessage?(connection, text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) { self?.onMessage?(connection, text) }
            @unknown default: break
            }
        }
    }

    func connectionDidClose(_ connection: WebSocketConnection, with error: Error?) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            // if cancel is originated from outside, clean up
            if self.connection === connection {
                self.connection = nil
                self.onDisconnected?(connection, error)
            }
            connection.delegate = nil
        }
    }
}

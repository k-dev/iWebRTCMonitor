//
//  SessionManager.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 23.05.2026.
//

@preconcurrency import WebRTC

/// Manages one room session for one monitor or viewer.
///
/// The owner creates this object and calls `start()` and `stop()`. It owns the
/// signaling client, shared local media, peer clients, and ICE buffers. The
/// session queue owns the peer map and ICE state. Socket and WebRTC callbacks
/// add work to that queue before they change session state.
final class SessionManager: @unchecked Sendable {

    nonisolated enum Peer: Sendable, Hashable {
        case monitor
        case viewer(id: String)
    }
    
    private var webRTCMedia: WebRTCLocalMedia
    private var iceStates: [Peer: IcePeerState<RTCIceCandidateMessage>] = [:]
    private let queue = DispatchQueue(label: "sessionQueue")
    private let queueKey = DispatchSpecificKey<Void>()
    private(set) var webRTCClients: [Peer : WebRTCClient]

    let signalingClient: SignalingClient
    let role: Role
    let peerID: String?
    
    var localVideoTrack: RTCVideoTrack? {
        return webRTCMedia.localVideoTrack
    }
    var onLocalVideoTrack: ((RTCVideoTrack) -> Void)?

    var selectedCaptureDevice: AVCaptureDevice? {
        get { webRTCMedia.currentDevice }
        set { if let newValue { webRTCMedia.switchCapturing(to: newValue) } }
    }
    var availableCaptureDevices: [AVCaptureDevice] { webRTCMedia.captureDevices }
    
    var onRemoteVideoTrack: ((RTCVideoTrack, Peer?) -> Void)?
    var onConnectionStateChange: ((RTCIceConnectionState, Peer?) -> Void)?
    
    init(serverAddress: String, roomID: String, role: Role, peerID: String? = nil) {
        // For detailed WebRTC logging level:
//        RTCSetMinDebugLogLevel(Logger.default.level.rtcSeverity())
        RTCSetMinDebugLogLevel(RTCLoggingSeverity.error)

        self.role = role
        self.webRTCClients = [:]
        self.signalingClient = SignalingClient(serverAddress: serverAddress, roomID: roomID, role: role, peerID: peerID, queue: queue)
        self.peerID = peerID
        self.webRTCMedia = WebRTCLocalMedia()

        queue.setSpecific(key: queueKey, value: ())

        self.setupSignaling()
        self.setupWebRTC(for: role)
    }
    
    deinit {
        stop()
    }
    
    private func peer(for client: WebRTCClient) -> Peer? {
        let element = webRTCClients.first { peer, webRTC in
            return webRTC == client
        }
        
        return element?.key
    }
    
    private func setupWebRTC(for role: Role) {
        queue.async { [weak self] in
            self?.webRTCMedia.prepareAudioTrack()
            if .viewer == role {
                self?.registerWebRTCClient(for: .monitor)
            }
            else {
                self?.webRTCMedia.onVideoCaptureStarted = { track in
                    self?.queue.async { [weak self] in
                        self?.onLocalVideoTrack?(track)
                    }
                }
                self?.webRTCMedia.prepareVideoTrackIfNeeded()
            }
        }
    }
    
    private func newWebRTCClient() -> WebRTCClient {
        let webRTCClient = WebRTCClient(factory: webRTCMedia.factory)
        webRTCClient.setup()
        
        webRTCClient.onICECandidate = { [weak self] candidate in
            self?.queue.async { [weak self] in
                let peer = self?.peer(for: webRTCClient)
                let msg = candidate.toMessage()
                self?.send(.iceCandidate(msg), to: peer)
            }
        }
        
        webRTCClient.onRemoteVideoTrack = { [weak self] track in
            self?.queue.async { [weak self] in
                let peer = self?.peer(for: webRTCClient)
                self?.onRemoteVideoTrack?(track, peer)
            }
        }
        
        webRTCClient.onConnectionStateChange = { [weak self] state in
            self?.queue.async { [weak self] in
                let peer = self?.peer(for: webRTCClient)
                Log(level: .debug, "WebRTC ICE state", state.rawValue, "peer", peer as Any, "client", ObjectIdentifier(webRTCClient), "registered peers", self?.webRTCClients.count as Any)
                self?.onConnectionStateChange?(state, peer)
            }
        }
        
        webRTCClient.onPeerConnectionNegotiate = { peer in
            Log(level: .debug, #function, peer)
        }
        
        webRTCClient.onVideoNegotiatedLevelsChange = { [weak self] levels in
            self?.queue.async { [weak self] in
                Log(level: .debug, "WebRTC capture update", "peer", self?.peer(for: webRTCClient) as Any, "client", ObjectIdentifier(webRTCClient), "levels", levels)
                self?.webRTCMedia.updateCapturing(for: levels)
            }
        }

        return webRTCClient
    }
    
    func cleanupPeer(_ peer: Peer) {
        Log(level: .debug, "WebRTC peer cleanup", peer, "client", webRTCClients[peer].map { ObjectIdentifier($0) } as Any)
        webRTCClients[peer]?.close()
        webRTCClients[peer] = nil
        iceStates[peer] = nil
    }
    
    func registerWebRTCClient(for peer: Peer) {
        // Only replacement ends an existing client lifetime. Initial attachment
        // must preserve candidates received before client creation.
        if webRTCClients[peer] != nil {
            cleanupPeer(peer)
        }
        
        let client = newWebRTCClient()
        webRTCClients[peer] = client
        Log(level: .debug, "WebRTC peer registered", peer, "client", ObjectIdentifier(client), "registered peers", webRTCClients.count)
    }
    
    // MARK: - Signaling
    
    private func setupSignaling() {
        signalingClient.onMessage = { [weak self] connection, message in
            self?.handleSignalingMessage(message)
        }
        signalingClient.onConnected = { _ in
            Log(category: .signaling, level: .debug, "Signaling connected")
        }
        signalingClient.onDisconnected = { conn, error in
            Log(category: .signaling, level: .status, "Signaling disconnected")
            if let error {
                Log(category: .signaling, level: .warning, "Error:", error.localizedDescription)
            }
        }
    }

    /// Opens signaling after the session queue confirms that no connection exists.
    func start() throws {
        try onSessionQueue {
            guard !signalingClient.isConnected else {
                throw SignalingError.alreadyConnected
            }
            try signalingClient.connect()
        }
    }

    /// Retires signaling, media capture, ICE state, and all peer clients.
    /// This method waits until the session queue completes that work.
    func stop() {
        onSessionQueue {
            self.signalingClient.disconnect()
            self.iceStates.removeAll()
            self.webRTCMedia.stop()
            self.webRTCClients.forEach { $1.close() }
            self.webRTCClients.removeAll()
        }
    }

    /// Runs lifecycle work on the session queue without synchronously re-entering it.
    private func onSessionQueue<T>(_ operation: () throws -> T) rethrows -> T {
        // Lifecycle calls can also run on the session queue, including deinit.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try operation()
        }
        else {
            return try queue.sync(execute: operation)
        }
    }
    
    // MARK: - Offer/Answer
    
    private func createAndSendOffer(to peer: Peer) {
        guard let client = webRTCClients[peer] else {
            return
        }
        
        client.announceVideo(for: role)
        if let audioTrack = webRTCMedia.localAudioTrack {
            client.addLocalMedia(audioTrack: audioTrack)
        }
        if let videoTrack = localVideoTrack {
            client.addLocalMedia(videoTrack: videoTrack)
        }
        
        client.createOffer { [weak self] sdp, error in
            self?.queue.async { [weak self] in
                self?.handleLocalSDP(sdp, error: error, type: .offer, to: peer, from: client)
            }
        }
    }
    
    private func createAndSendAnswer(to peer: Peer) {
        guard let client = webRTCClients[peer] else {
            return
        }
        
        client.announceVideo(for: role)
        if let audioTrack = webRTCMedia.localAudioTrack {
            client.addLocalMedia(audioTrack: audioTrack)
        }
        if let videoTrack = localVideoTrack {
            client.addLocalMedia(videoTrack: videoTrack)
        }
        
        client.createAnswer { [weak self] sdp, error in
            self?.queue.async { [weak self] in
                self?.handleLocalSDP(sdp, error: error, type: .answer, to: peer, from: client)
            }
        }
    }
    
    /// Runs on the session queue after the native offer or answer completion.
    /// The client identity prevents a retired client from sending local SDP.
    func handleLocalSDP(_ sdp: RTCSessionDescription?, error: Error?, type: RTCSdpType,
                        to peer: Peer, from client: WebRTCClient) {
        guard webRTCClients[peer] === client else {
            Log(category: .signaling, level: .warning, "Error sending \(type.toString()): obsoleteClient")
            return
        }
        guard let sdp else {
            Log(category: .signaling, level: .warning, "Create and send \(type.toString()) failed: \(error?.localizedDescription ?? "")")
            return
        }
        switch type {
        case .offer:
            send(.offer(sdp.toMessage()), to: peer)
        case .answer:
            Log(category: .signaling, level: .verbose, "Sending local SDP:", sdp)
            send(.answer(sdp.toMessage()), to: peer)
        default:
            return
        }
    }

    private func handleOffer(_ message: RTCSessionDescriptionMessage, from peer: Peer) {
        // Checking for Glare condition and handling it with Perfect negotiation:
        // polite peer is .viewer
        // impolite peer is .monitor
        // 1. `client != nil` means that we already must have sent an Offer.
        if let existingClient = webRTCClients[peer] {
            // 2. Checking our peer kindness and is there a Glare.
            if .monitor == role && existingClient.hasSentOffer() {
                // Since we are .monitor, ignore counter-offer impolitely.
                return
            }
            // Polite peer needs to make 'rollback'. It is handled by WebRTC in `setRemoteDescription()`.
        }
        else {
            // `client == nil` means that we have not sent an offer yet. Handle it.
            registerWebRTCClient(for: peer)
        }

        guard let client = webRTCClients[peer] else {
            return
        }
        client.setRemoteSDP(message) { [weak self, weak client] error in
            if let error {
                Log(category: .signaling, level: .warning, "Handle offer failed: \(error)")
                return
            }

            self?.queue.async { [weak self, client] in
                // A weak reference cannot resolve to a different object even if
                // an allocator reuses its address after removal.
                guard let self, let client, self.webRTCClients[peer] === client else {
                    return
                }

                self.handleICECandidates(from: peer)
                self.createAndSendAnswer(to: peer)
            }
        }
    }

    private func handleAnswer(_ message: RTCSessionDescriptionMessage, from peer: Peer) {
        guard let client = webRTCClients[peer] else {
            return
        }
        client.setRemoteSDP(message) { [weak self, weak client] error in
            if let error {
                Log(category: .signaling, level: .warning, "Handle answer failed:", error.localizedDescription)
                return
            }

            self?.queue.async { [weak self, client] in
                guard let self, let client, self.webRTCClients[peer] === client else {
                    return
                }
                self.handleICECandidates(from: peer)
            }
        }
    }
    
    // MARK: - ICE
    
    private func handleICECandidates(from peer: Peer) {
        var buffer = iceStates[peer] ?? IcePeerState<RTCIceCandidateMessage>()
        let candidates = buffer.markReady()
        iceStates[peer] = buffer
        candidates.forEach { submitICECandidate($0, from: peer) }
    }
    
    private func handleICECandidate(message: RTCIceCandidateMessage, from peer: Peer) {
        var state = iceStates[peer] ?? IcePeerState<RTCIceCandidateMessage>()
        let message = state.receive(message)
        iceStates[peer] = state
        if let message {
            submitICECandidate(message, from: peer)
        }
    }

    private func submitICECandidate(_ message: RTCIceCandidateMessage, from peer: Peer) {
        guard let webRTCClient = webRTCClients[peer] else {
            Log(category: .signaling, level: .warning, "No client found for peer", peer)
            return
        }
        
        assert(webRTCClient.hasRemoteDescription, "Should be true")
        
        let candidate = RTCIceCandidate.from(message)
        webRTCClient.addICECandidate(candidate) { error in
            if let error {
                Log(category: .signaling, level: .warning, "Error adding ICE candidate", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Message handling
    
    private func handleSignalingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(SignalingEnvelope.self, from: data)
        else {
            return
        }
        
        do {
            switch envelope.message {
            case .offer(let sdp):
                handleOffer(sdp, from: try sender(from: envelope))
            case .answer(let sdp):
                handleAnswer(sdp, from: try sender(from: envelope))
            case .iceCandidate(let msg):
                handleICECandidate(message: msg, from: try sender(from: envelope))
            case .viewerConnected(let viewerID):
                let peer: Peer = .viewer(id: viewerID)
                registerWebRTCClient(for: peer)
                createAndSendOffer(to: peer)
            case .monitorConnected:
                registerWebRTCClient(for: .monitor)
                // When `.monitor` was disconnected, it won't receive `.viewerConnected` event.
                // Sending offer from `.viewer` instead.
                createAndSendOffer(to: .monitor)
                break
            }
        } catch {
            Log(category: .signaling, level: .error, error.localizedDescription)
        }
    }
    
    private func sender(from envelope: SignalingEnvelope) throws -> Peer {
        if .viewer == role, peerID == envelope.to, nil == envelope.from {
            return .monitor
        }
        else if nil == envelope.to, .monitor == role, let vId = envelope.from {
            return .viewer(id: vId)
        }
        
        throw SignalingError.incorrectEnvelopeFrom
    }

    // MARK: - Send

    private func encode(_ message: SignalingMessage, to peer: Peer?) throws -> String {
        let data = try JSONEncoder().encode(message)
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EncodingError.invalidValue(message, .init(codingPath: [], debugDescription: "Expected signaling object"))
        }
        if case .viewer(let peerID) = peer {
            dict["to"] = peerID
        }
        else if case .viewer = role {
            dict["from"] = peerID
        }
        let encoded = try JSONSerialization.data(withJSONObject: dict)
        return String(decoding: encoded, as: UTF8.self)
    }

    private func send(_ message: SignalingMessage, to peer: Peer?) {
        do {
            guard let connection = signalingClient.connection else {
                throw SignalingError.notConnected
            }
            try signalingClient.send(encode(message, to: peer), using: connection)
        }
        catch {
            Log(category: .signaling, level: .warning, "Signaling send failed", error)
        }
    }

}

// MARK: - Helpers

extension RTCSdpType {
    func toString() -> String {
        switch self {
        case .offer: return "offer"
        case .answer: return "answer"
        case .prAnswer: return "pranswer"
        case .rollback: return "rollback"
        @unknown default: return "offer"
        }
    }
    
    static func from(_ string: String) -> RTCSdpType? {
        switch string {
        case "offer": return .offer
        case "answer": return .answer
        case "pranswer": return .prAnswer
        case "rollback": return .rollback
        default: return nil
        }
    }
}

extension RTCSessionDescription {
    
    func toMessage() -> RTCSessionDescriptionMessage {
        return RTCSessionDescriptionMessage(sdp: sdp, type: type.toString())
    }
}

extension RTCIceCandidate {
    
    func toMessage() -> RTCIceCandidateMessage {
        return RTCIceCandidateMessage(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
    
    static func from(_ message: RTCIceCandidateMessage) -> RTCIceCandidate {
        return RTCIceCandidate(sdp: message.sdp, sdpMLineIndex: message.sdpMLineIndex, sdpMid: message.sdpMid)
    }
}

#if DEBUG
// MARK: - For testing race conditions
extension SessionManager {
    func checkedContinuationSnapshot(with closure: @Sendable @escaping (SessionManager?) -> Void) async {
        await withCheckedContinuation { [weak self] continuation in
            self?.queue.async { [weak self] in
                if let self {
                    closure(self)
                }
                continuation.resume()
            }
        }
    }
}
#endif

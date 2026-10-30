//
//  WebRTCClient.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 09.05.2026.
//

import Foundation
@preconcurrency import WebRTC

enum WebRTCClientError: Error {
    case incorrectMessageToSDP
}

fileprivate let audioStreamID = "stream0"
fileprivate let videoStreamID = "stream0"

/// Owns one peer connection and its WebRTC callback bridge.
///
/// `SessionManager` creates one client for each peer and releases it during peer
/// cleanup. The client queue serializes operations that this type enqueues on
/// the peer connection. `PeerConnectionDelegate` forwards native callbacks
/// through its own queue. The configured closures return them to the session queue.
final class WebRTCClient: NSObject, @unchecked Sendable {
    
    private static func stunServers() -> [RTCIceServer] {
        [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun2.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun3.l.google.com:19302"])
        ]
    }
    
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private let peerDelegate: PeerConnectionDelegate?
    private let queue = DispatchQueue(label: "webRTCClient")
    
    var hasRemoteDescription: Bool {
        return peerConnection?.remoteDescription != nil
    }

    var onICECandidate: ((RTCIceCandidate) -> Void)?
    var onRemoteVideoTrack: ((RTCVideoTrack) -> Void)?
    var onConnectionStateChange: ((RTCIceConnectionState) -> Void)?
    var onPeerConnectionNegotiate: ((RTCPeerConnection) -> Void)?
    var onVideoNegotiatedLevelsChange: (([String]) -> Void)?
    
    convenience override init() {
        self.init(factory: nil)
    }
    
    init(factory: RTCPeerConnectionFactory?) {
        RTCInitializeSSL()
        peerDelegate = PeerConnectionDelegate()

        self.factory = factory ?? RTCPeerConnectionFactory()
        
        super.init()
    }
    
    deinit {
        close()
    }
    
    /// Creates the native peer connection and connects its delegate callbacks.
    func setup() {
        debugPrint(#function)
        let config = RTCConfiguration()
        config.iceServers = Self.stunServers()
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerDelegate?.onICECandidate = { [weak self] peerConnection, candidate in
            self?.onICECandidate?(candidate)
        }
        
        peerDelegate?.onRemoteVideoTrack = { [weak self] peerConnection, videoTrack in
            self?.onRemoteVideoTrack?(videoTrack)
        }
        
        peerDelegate?.onICEConnectionStateChange = { [weak self] peerConnection, state in
            if state == .failed {
                Log(level: .warning, "onICEConnectionStateChange: FAILED")
            }
            self?.onConnectionStateChange?(state)
        }
        
        peerDelegate?.onSignalingState = { peerConnection, state in
            Log(level: .verbose, "Peer state changed", state.rawValue)
        }
        
        peerDelegate?.onShouldNegotiate = { [weak self] peerConnection in
            self?.onPeerConnectionNegotiate?(peerConnection)
        }
        
        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: peerDelegate
        )

#if DEBUG
        debugPrint("WebRTCClient", Unmanaged.passUnretained(self).toOpaque(),
                   "peerConnection", Unmanaged.passUnretained(peerConnection!).toOpaque())
#endif
    }
    
    func addLocalMedia(audioTrack: RTCAudioTrack) {
        queue.async { [weak self] in
            self?.peerConnection?.add(audioTrack, streamIds: [audioStreamID])
        }
    }

    func addLocalMedia(videoTrack: RTCVideoTrack) {
        queue.async { [weak self] in
            self?.addLocalMediaOnQueue(videoTrack: videoTrack)
        }
    }
    
    func announceVideo(for role: Role) {
        queue.async { [weak self] in
            guard nil == self?.peerConnection?.transceivers.first(where: { $0.mediaType == .video }) else {
                Log(level: .error, "Attempt to add already existing video transceiver to " +
                    "\(String(describing: self?.peerConnection))")
                return
            }
            
            let options = RTCRtpTransceiverInit()
            switch role {
            case .viewer:   options.direction = .recvOnly
            case .monitor:  options.direction = .sendOnly
            }
            options.streamIds = [videoStreamID]
//            options.sendEncodings = [encodingParams(for: levels)]
            
            self?.peerConnection?.addTransceiver(of: .video, init: options)
        }
    }

    // Ranking by MaxMBPS via H264Levels table
    private func levelWeight(_ profileLevelId: String) -> Int {
        H264Levels.maxMBPS(for: profileLevelId.suffix(2))
    }

    private func addLocalMediaOnQueue(videoTrack: RTCVideoTrack) {
        guard let peerConnection else {
            Log(level: .error, "No peerConnection for WebRTCClient <\(Unmanaged.passUnretained(self).toOpaque())>")
            return
        }
        
        // Mandatory to call announceVideo(for: Role) beforehand. Otherwise there is nowhere to add a video track.
        Log(level: .verbose, "Transceivers count", peerConnection.transceivers.count, "for", peerConnection)
        if let transceiver = peerConnection.transceivers.first(where: { $0.mediaType == .video }) {
            transceiver.sender.track = videoTrack

            // Fix for .monitor peer reconnection. Viewer sends new offer, monitor must answer with
            // valid videoTrack AND correct direction. WebRTC implicitly marks video transceiver as inactive
            // when monitor was disconnected. Here we mark it back as `.sendonly`
            var error: NSError?
            transceiver.setDirection(.sendOnly, error: &error)
            if let error = error {
                Log(level: .error, "Failed to set transceiver direction: \(error.localizedDescription)")
            }
        }
    }
    
    /// Creates and installs local offer SDP. Completion can run on a WebRTC callback context.
    func createOffer(completion: @Sendable @escaping (RTCSessionDescription?, Error?) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)

        queue.async { [weak self] in
            self?.peerConnection?.offer(for: constraints) { [weak self] sdp, error in
                if let sdp {
                    self?.setLocalSDP(sdp) { error in
                        if let error {
                            completion(nil, error)
                        }
                        else {
                            completion(sdp, nil)
                        }
                    }
                }
                else {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Creates and installs local answer SDP. Completion can run on a WebRTC callback context.
    func createAnswer(completion: @Sendable @escaping (RTCSessionDescription?, Error?) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)
        
        queue.async { [weak self] in
            self?.peerConnection?.answer(for: constraints) { [weak self] sdp, error in
                if let sdp {
                    self?.setLocalSDP(sdp) { error in
                        if let error {
                            completion(nil, error)
                        }
                        else {
                            completion(sdp, nil)
                        }
                    }
                }
                else {
                    completion(nil, error)
                }
            }
        }
    }
    
    private func setLocalSDP(_ sdp: RTCSessionDescription, completion: @Sendable @escaping (Error?) -> Void) {
        Log(level: .debug, "Setting local negotiated levels:", sdp.negotiatedLevels())
        peerConnection?.setLocalDescription(sdp, completionHandler: completion)
    }
    
    /// Schedules remote SDP installation on the client queue.
    /// The level callback occurs before WebRTC reports SDP installation success.
    func setRemoteSDP(_ message: RTCSessionDescriptionMessage, completion: @Sendable @escaping (Error?) -> Void) {
        guard let type = RTCSdpType.from(message.type) else {
            completion(WebRTCClientError.incorrectMessageToSDP)
            return
        }

        let sdp = RTCSessionDescription(type: type, sdp: message.sdp)
        Log(level: .verbose, "Remote SDP:", message)
        
        let levels = sdp.negotiatedLevels()
        Log(level: .verbose, "Remote Levels:", levels)
        
        onVideoNegotiatedLevelsChange?(levels)
        
        queue.async { [weak self] in
            self?.peerConnection?.setRemoteDescription(sdp, completionHandler: completion)
        }
    }
    
    func addICECandidate(_ candidate: RTCIceCandidate, completion: @Sendable @escaping (Error?) -> Void) {
        queue.async { [weak self] in
            self?.peerConnection?.add(candidate, completionHandler: completion)
        }
    }
    
    /// Schedules native peer connection release on the client queue.
    func close() {
        Log(level: .verbose, "Connection is closing for", self)
        queue.async { [weak self] in
            self?.peerConnection?.close()
            self?.peerConnection = nil
        }
    }
    
    func hasSentOffer() -> Bool {
        guard let peerConnection else {
            return false
        }

        debugPrint("-- signalingState", peerConnection.signalingState.rawValue)
        debugPrint("-- localDescription", peerConnection.localDescription as Any)
        return (peerConnection.signalingState != .stable || peerConnection.localDescription != nil)
    }
}

extension CMVideoFormatDescription: @retroactive Comparable {

    var width: Int32 {
        CMVideoFormatDescriptionGetDimensions(self).width
    }

    var height: Int32 {
        CMVideoFormatDescriptionGetDimensions(self).height
    }
    
    public static func < (lhs: CMFormatDescription, rhs: CMFormatDescription) -> Bool {
        let left = lhs.width * lhs.height
        let right = rhs.width * rhs.height
        
        return left < right
    }
}

extension RTCVideoEncoderFactory {
    
    func localH264Capabilities() -> [String] {
        var supportedLevels: [String] = []
        
        for codec in self.supportedCodecs() {
            if codec.name == "H264", let profileLevelId = codec.parameters["profile-level-id"] {
                supportedLevels.append(profileLevelId)
            }
        }
        return supportedLevels
    }
}

extension RTCRtpSender {
    /// Configures all active video encodings to hold resolution fixed and
    /// degrade framerate under bandwidth/CPU pressure instead of scaling
    /// resolution up/down. Call after the sender/transceiver's encodings
    /// are set (e.g. right after addTransceiver, and again after any
    /// subsequent setParameters call that might reset them).
    func applyMaintainResolutionPreference() {
        Log(level: .verbose, "Applying maintain resolution preference")
        let params = parameters
        params.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
        parameters = params
    }
}

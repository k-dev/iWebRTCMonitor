//
//  PeerConnectionDelegate.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 09.05.2026.
//

@preconcurrency import WebRTC

/// Bridges native peer-connection callbacks to `WebRTCClient` closures.
///
/// A `WebRTCClient` creates and retains this delegate. Its callback queue
/// serializes the closures that forward native events to the session manager.
final class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {

    // MARK: - Queue
    private let queue = DispatchQueue(label: "peerConnectionDelegate.callbacks")
    
    // MARK: - Callbacks
    var onICECandidate: ((RTCPeerConnection, RTCIceCandidate) -> Void)?
    var onICEConnectionStateChange: ((RTCPeerConnection, RTCIceConnectionState) -> Void)?
    var onRemoteVideoTrack: ((RTCPeerConnection, RTCVideoTrack) -> Void)?
    var onShouldNegotiate: ((RTCPeerConnection) -> Void)?
    var onSignalingState: ((RTCPeerConnection, RTCSignalingState) -> Void)?
    
    // MARK: - RTCPeerConnectionDelegate
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Log(level: .debug, #function, candidate)
        queue.async { [weak self] in
            self?.onICECandidate?(peerConnection, candidate)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Log(level: .debug, #function, newState.rawValue)
        queue.async { [weak self] in
            self?.onICEConnectionStateChange?(peerConnection, newState)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Log(level: .debug, #function, "Received stream.videoTracks.count:", stream.videoTracks.count)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        Log(level: .debug, #function, transceiver)
        
        guard transceiver.mediaType == .video, let track = transceiver.receiver.track as? RTCVideoTrack else {
            return
        }

        Log(level: .verbose, "Received transceiver.receiver.track of video mediaType")
        
        queue.async { [weak self] in
            self?.onRemoteVideoTrack?(peerConnection, track)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Log(level: .debug, #function)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Log(level: .debug, #function, stateChanged.rawValue)
        queue.async { [weak self] in
            self?.onSignalingState?(peerConnection, stateChanged)
        }
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Log(level: .debug, #function)
        queue.async { [weak self] in
            self?.onShouldNegotiate?(peerConnection)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Log(level: .debug, #function, newState.rawValue)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Log(level: .debug, #function)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Log(level: .debug, #function)
    }

}

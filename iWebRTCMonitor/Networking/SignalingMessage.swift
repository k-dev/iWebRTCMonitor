//
//  SignalingMessage.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 23.05.2026.
//

/// Transfers one SDP description in a signaling message.
struct RTCSessionDescriptionMessage: Codable, Sendable {
    let sdp: String
    let type: String
}

/// Transfers one ICE candidate in a signaling message.
struct RTCIceCandidateMessage: Codable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
}

/// Defines the message payloads used by the signaling server.
enum SignalingMessage: Codable {
    case offer(RTCSessionDescriptionMessage)
    case answer(RTCSessionDescriptionMessage)
    case iceCandidate(RTCIceCandidateMessage)
    case viewerConnected(viewerID: String)
    case monitorConnected
    
    enum CodingKeys: String, CodingKey {
        case type, payload, viewerID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .offer(let sdp):
            try container.encode("offer", forKey: .type)
            try container.encode(sdp, forKey: .payload)
        case .answer(let sdp):
            try container.encode("answer", forKey: .type)
            try container.encode(sdp, forKey: .payload)
        case .iceCandidate(let candidate):
            try container.encode("iceCandidate", forKey: .type)
            try container.encode(candidate, forKey: .payload)
        case .viewerConnected(let viewerID):
            try container.encode("viewerConnected", forKey: .type)
            try container.encode(viewerID, forKey: .viewerID)
        case .monitorConnected:
            try container.encode("monitorConnected", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "offer":
            self = .offer(try container.decode(RTCSessionDescriptionMessage.self, forKey: .payload))
        case "answer":
            self = .answer(try container.decode(RTCSessionDescriptionMessage.self, forKey: .payload))
        case "iceCandidate":
            self = .iceCandidate(try container.decode(RTCIceCandidateMessage.self, forKey: .payload))
        case "viewerConnected":
            self = .viewerConnected(viewerID: try container.decode(String.self, forKey: .viewerID))
        case "monitorConnected":
            self = .monitorConnected
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }
}

struct SignalingEnvelope: Codable {
    
    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    
    let from: String?
    let to: String?
    let message: SignalingMessage
    
    // Flat decoding — message fields at top level
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        from = try? container.decode(String.self, forKey: DynamicKey("from"))
        to = try? container.decode(String.self, forKey: DynamicKey("to"))
        message = try SignalingMessage(from: decoder)
    }
    
    func encode(to encoder: Encoder) throws {
        try message.encode(to: encoder)
    }
}

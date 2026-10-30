//
//  ViewerViewModel.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 31.05.2026.
//

import Combine
import Foundation
import WebRTC
import SwiftUI

/// Owns viewer UI state and one viewer session.
///
/// `ViewerView` creates and owns this object. It creates its session manager on first use.
/// Session callbacks transfer published-state updates to the main actor.
@MainActor
class ViewerViewModel: ObservableObject {
    
    @Published private(set) var state: RoomViewModel.State = .initial {
        didSet {
            viewTitle = "Viewer" + " " + state.emojiIndicator
            stateRecords.append(Record(message: state.rawValue))
            Log(level: .verbose, "Viewer connection state: ", state.rawValue)
        }
    }
    @Published private(set) var stateRecords: [Record] = []
    @Published private(set) var viewTitle: String = "Viewer"
    @Published private(set) var videoTrack: RTCVideoTrack?
    private(set) var roomID: String
    private(set) var urlString: String
    private(set) var viewerID: String
    
    lazy private var sessionManager: SessionManager = {
        SessionManager(serverAddress: urlString, roomID: roomID, role: .viewer, peerID: viewerID)
    }()
    
    init(roomID: String, urlString: String, viewerID: String = UUID().uuidString) {
        self.roomID = roomID
        self.urlString = urlString
        self.viewerID = viewerID
        
        Log(level: .debug, "Instantiated .viewer \(Unmanaged.passUnretained(self).toOpaque())")
    }
    
    /// Configures callbacks and starts the viewer signaling session.
    func setup() async {
        guard state == .initial || state == .failed else {
            return
        }
        
        sessionManager.onConnectionStateChange = { [weak self] iceState, _ in
            guard let self else { return }

            Log(level: .debug, "viewer\t state: \(iceState)")
            
            Task.detached { @MainActor [weak self] in
                self?.updateState(iceState)
            }
        }
        
        sessionManager.onRemoteVideoTrack = { [weak self] videoTrack, peer in
            Log(level: .verbose, "Received video track")
            Task.detached { @MainActor [weak self] in
                self?.videoTrack = videoTrack
            }
        }
        
        do {
            try sessionManager.start()
            state = .pending
        } catch {
            state = .failed
            Log(level: .error, error.localizedDescription)
        }
    }
    
    func updateState(_ iceState: RTCIceConnectionState) {
        switch iceState {
        case .new:
            state = .initial
        case .checking:
            state = .pending
        case .connected, .completed:
            state = .ready
        case .closed, .disconnected, .failed:
            state = .failed
        default:
            Log(level: .warning, "Ice connection state not handled")
        }
    }
}

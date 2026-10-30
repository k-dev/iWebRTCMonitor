//
//  RoomViewModel.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 26.05.2026.
//

import Combine
import WebRTC

struct Record: LogRowRepresentable {
    var id = UUID()
    var time: Date = .now
    var message: String
}

/// Owns monitor UI state and one monitor session.
///
/// `CameraView` creates and owns this object. It creates its session manager on first use.
/// Session callbacks transfer published-state updates to the main actor.
@MainActor
class RoomViewModel: ObservableObject {
    
    enum State: String {
        case initial
        case pending
        case permissionRequired
        case ready
        case failed
    }
    
    @Published private(set) var viewTitle: String = "Camera"
    @Published private(set) var localVideoTrack: RTCVideoTrack?
    @Published private(set) var state: State = .initial
    @Published private(set) var stateRecords: [Record] = []
    @Published private(set) var permissionFailure: CapturePermissions.Failure?
    
    var roomIDQuery: String {
        // FIXME: as a backup need to hardcode a scheme
        let scheme = Bundle.main.bundleIdentifier ?? ""
        return scheme + "://join?roomID=" + roomID
    }

    private(set) var roomID: String
    private(set) var urlString: String
    private(set) var role: Role
    private(set) var peerID: String
    private let capturePermissions: CapturePermissions
    
    lazy private var sessionManager: SessionManager = {
        SessionManager(serverAddress: urlString, roomID: roomID, role: role)
    }()
    
    init(roomID: String, urlString: String, role: Role, permissions: CapturePermissions? = nil) {
        self.roomID = roomID
        self.urlString = urlString
        self.role = role
        self.peerID = UUID().uuidString
        self.capturePermissions = permissions ?? CapturePermissions()

        Log(level: .debug, self)
    }
    
    /// Requires camera and microphone access before creating capture resources or signaling.
    func setup() async {
        guard state == .initial || state == .failed || state == .permissionRequired else {
            return
        }

        updateState(.checking)
        permissionFailure = nil

        let failure = await capturePermissions.check()
        guard !Task.isCancelled else {
            updateState(.new)
            return
        }
        if let failure {
            permissionFailure = failure
            state = .permissionRequired
            viewTitle = "Camera " + state.emojiIndicator
            stateRecords.append(Record(message: failure.title))
            Log(level: .warning, failure.title)
            return
        }
        
        sessionManager.onConnectionStateChange = { [weak self] iceState, peer in
            guard let self else { return }

            Log(level: .verbose, "\(self.role)\t state: \(iceState)")
            
            Task.detached { @MainActor [weak self] in
                self?.updateState(iceState, peer: peer)
            }
        }
        
        sessionManager.onLocalVideoTrack = { [weak self] track in
            DispatchQueue.main.async {
                self?.localVideoTrack = track
            }
        }
        
        localVideoTrack = sessionManager.localVideoTrack

        do {
            try sessionManager.start()
        }
        catch {
            Log(level: .error, error.localizedDescription)
            updateState(.failed)
        }
    }
    
    func updateState(_ iceState: RTCIceConnectionState, peer: SessionManager.Peer? = nil) {
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
            Log(level: .warning, "Unhandled RTCIceConnectionState", iceState)
        }
        
        var stateDescription = state.rawValue
        if case .viewer(let id) = peer {
            stateDescription += " (viewerID - \(id))"
        }
        
        viewTitle = "Camera" + " " + state.emojiIndicator
        stateRecords.append(Record(message: stateDescription))
        Log(level: .verbose, "Camera connection state", stateDescription)
    }
    
    func switchCamera() {
        let devices = sessionManager.availableCaptureDevices
        guard devices.count > 0 else {
            return
        }
        
        var nextIdx = 0
        if let device = sessionManager.selectedCaptureDevice {
            if let idx = devices.firstIndex(of: device) {
                nextIdx = devices.index(after: idx)
            }
        }

        nextIdx = nextIdx % devices.count
        let nextDevice = devices[nextIdx]
        sessionManager.selectedCaptureDevice = nextDevice
    }
}

extension RoomViewModel: CustomStringConvertible {
    var description: String {
        return """
            RoomViewModel <\(Unmanaged.passUnretained(self).toOpaque())> {
                roomID: \(roomID)
                urlString: \(urlString)
                role: \(role)
                peerID: \(peerID)
                localVideoTrack: \(localVideoTrack != nil ? String(describing: localVideoTrack!) : "<nil>")
                state: \(state)
            }
            """
    }
}

extension RoomViewModel.State {
    var emojiIndicator: String {
        switch self {
        case .initial:
            return "⚪️"
        case .pending:
            return "🟡"
        case .ready:
            return "🟢"
        case .failed, .permissionRequired:
            return "🔴"
        }
    }
}

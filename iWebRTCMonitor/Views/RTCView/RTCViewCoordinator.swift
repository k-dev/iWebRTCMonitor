//
//  RTCViewCoordinator.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.06.2026.
//

@preconcurrency import WebRTC

/// Attaches one WebRTC video track to one platform video view.
///
/// The SwiftUI representable creates and owns this coordinator. View attachment
/// runs on the main queue. The WebRTC video-size callback does not state its
/// execution context; callers must make UI changes on the main actor.
@MainActor
class RTCViewCoordinator {
    
#if os(macOS)
    typealias _RTCView = RTCMTLNSVideoView
#elseif os(iOS)
    typealias _RTCView = RTCMTLVideoView
#endif

    var onVideoSizeChanged: ((CGSize) -> Void)?
    
    private var currentTrack: RTCVideoTrack?
    private var currentView: _RTCView?
    
    init(onVideoSizeChanged: ((CGSize) -> Void)?) {
        self.onVideoSizeChanged = onVideoSizeChanged
    }
    
    func update(track: RTCVideoTrack?, with view: _RTCView) {
        guard currentTrack != track || currentView != view else {
            debugPrint("Tracks \(currentTrack == track) and views \(currentView == view) are the same")
            return
        }
        
        view.delegate = self

        if let oldTrack = currentTrack, let oldView = currentView {
            oldTrack.remove(oldView)
        }
        
        currentTrack = track
        currentView = view

        DispatchQueue.main.async {
            track?.add(view)
        }
    }

    deinit {
        if let track = currentTrack, let view = currentView {
            track.remove(view)
        }
    }
}

extension RTCViewCoordinator: RTCVideoViewDelegate {

    func videoView(_ videoView: any RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        onVideoSizeChanged?(size)
    }
}

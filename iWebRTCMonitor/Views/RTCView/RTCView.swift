//
//  RTCView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.06.2026.
//

import WebRTC

@MainActor
struct RTCView {
    
    var videoTrack: RTCVideoTrack?
    
    var onVideoSizeChanged: ((CGSize) -> Void)?
    
    func makeCoordinator() -> RTCViewCoordinator {
        return RTCViewCoordinator(onVideoSizeChanged: onVideoSizeChanged)
    }
}

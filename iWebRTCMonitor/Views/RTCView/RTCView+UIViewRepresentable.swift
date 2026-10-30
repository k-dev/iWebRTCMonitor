//
//  RTCView+UIViewRepresentable.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.06.2026.
//

import WebRTC
import SwiftUI

extension RTCView: UIViewRepresentable {
    
    func updateUIView(_ rtcView: RTCMTLVideoView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(track: videoTrack, with: rtcView)
        }
    }
    
    public func makeUIView(context: Context) -> RTCMTLVideoView {
        let rtcView = RTCMTLVideoView(frame: .zero)
        rtcView.backgroundColor = .black
        rtcView.translatesAutoresizingMaskIntoConstraints = false
        rtcView.videoContentMode = .scaleAspectFit
        context.coordinator.update(track: videoTrack, with: rtcView)

        return rtcView
    }
}

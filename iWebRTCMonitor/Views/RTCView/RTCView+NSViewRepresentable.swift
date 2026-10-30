//
//  RTCView+NSViewRepresentable.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.06.2026.
//

import WebRTC
import SwiftUI

extension RTCView: NSViewRepresentable {
    
    func updateNSView(_ rtcView: RTCMTLNSVideoView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(track: videoTrack, with: rtcView)
        }
    }
    
    public func makeNSView(context: Context) -> RTCMTLNSVideoView {
        let rtcView = RTCMTLNSVideoView()
        rtcView.wantsLayer = true
        rtcView.layer?.backgroundColor = .black
        rtcView.translatesAutoresizingMaskIntoConstraints = false
        
        context.coordinator.update(track: videoTrack, with: rtcView)

        return rtcView
    }
}

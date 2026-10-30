//
//  RTCSessionDescription+Levels.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.10.2026.
//

import WebRTC

extension RTCSessionDescription {
    
    func negotiatedLevels() -> [String] {
        var levels: [String] = []
        let sdpString = sdp
        let pattern = "profile-level-id=([a-fA-F0-9]{6})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return levels
        }
        
        let nsString = sdpString as NSString
        let results = regex.matches(in: sdpString, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in results {
            levels.append(nsString.substring(with: match.range(at: 1)))
        }
        return levels
    }
}

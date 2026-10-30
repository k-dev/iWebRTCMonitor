//
//  H264Levels.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.10.2026.
//

import AVFoundation

enum H264Levels {
    // Hex values mapped to Max Macroblocks Per Second (MaxMBPS)
    // 3 bytes, PPPPXX, where 42e0 (of PPPP) means H.264 protocol. XX are as below
    static func maxMBPS(for levelHex: any StringProtocol) -> Int {
        switch levelHex.lowercased() {
        case "1f": return 108_000   // Level 3.1 (e.g., 42e01f)
        case "28", "29": return 245_760   // Level 4.0
        case "2a": return 522_240   // Level 4.2
        case "32": return 589_824   // Level 5.0
        case "33": return 983_040   // Level 5.1
        case "34": return 2_073_600 // Level 5.2 (e.g., 640c34)
        default:   return 108_000   // Safe fallback to Level 3.1
        }
    }
    
    static func videoFormat(for levelID: String, desiredSize: CGSize, minFps: Int) -> (size: CGSize, fps: Double) {
        let maxMBPS = H264Levels.maxMBPS(for: levelID.suffix(2))
        let maxMacroblocks = Double(maxMBPS / minFps)

        var mbWidth = ceil(desiredSize.width / 16.0)
        var mbHeight = ceil(desiredSize.height / 16.0)
        
        let kWH = maxMacroblocks / (mbWidth * mbHeight)
        
        // If our desired size is too big, scale DOWN proportionally
        if kWH < 1.0 {
            let scaleFactor = sqrt(kWH)
            mbWidth = mbWidth * scaleFactor  // MULTIPLY, do not divide
            mbHeight = mbHeight * scaleFactor
        }
        
        // Safety check just in case rounding pushed us slightly over
        while (mbWidth * mbHeight) > maxMacroblocks {
            // Reduce by a fraction to maintain aspect ratio, rather than -1
            mbWidth = mbWidth * 0.99
            mbHeight = mbHeight * 0.99
        }

        let safeMaxFPS = Double(maxMBPS) / Double(mbWidth * mbHeight)
        
        return (CGSize(width: Int(mbWidth) << 4, height: Int(mbHeight) << 4), safeMaxFPS)
    }
}

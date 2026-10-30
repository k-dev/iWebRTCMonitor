//
//  Logger+RTCLoggingSeverity.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.10.2026.
//

import WebRTC

extension Logger.Level {

    func rtcSeverity() -> RTCLoggingSeverity {
        switch self {
        case .debug:
            return RTCLoggingSeverity.verbose
        case .verbose:
            return RTCLoggingSeverity.verbose
        case .status:
            return RTCLoggingSeverity.info
        case .warning:
            return RTCLoggingSeverity.warning
        case .error:
            return RTCLoggingSeverity.error
        }
    }
}

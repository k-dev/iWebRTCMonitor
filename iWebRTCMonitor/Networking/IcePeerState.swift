//
//  Configuration.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 12.10.2026.
//

/// Buffers one peer's ICE candidates until remote SDP succeeds.
///
/// `SessionManager` owns each value on its session queue. The value has no
/// independent synchronization.
struct IcePeerState<Message> {
    private(set) var isReady = false
    private var pending: [Message] = []

    mutating func receive(_ message: Message) -> Message? {
        if isReady {
            return message
        }

        pending.append(message)
        return nil
    }

    /// Called only after successful remote-description application.
    mutating func markReady() -> [Message] {
        defer { pending.removeAll() }
        isReady = true
        return pending
    }
}

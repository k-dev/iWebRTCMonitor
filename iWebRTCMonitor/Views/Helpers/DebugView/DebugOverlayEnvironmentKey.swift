//
//  DebugOverlayEnvironmentKey.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 01.07.2026.
//

import SwiftUI

private struct ShowDebugOverlayKey: EnvironmentKey {

    static let defaultValue: Bool = false
}

extension EnvironmentValues {

    var isShowingDebugOverlay: Bool {
        get { self[ShowDebugOverlayKey.self] }
        set { self[ShowDebugOverlayKey.self] = newValue }
    }
}

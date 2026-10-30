//
//  iWebRTCMonitorApp.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 09.05.2026.
//

import SwiftUI

/// Starts the SwiftUI application and installs the platform app delegate.
@main
struct iWebRTCMonitorApp: App {
    
#if os(macOS)
    @NSApplicationDelegateAdaptor
#elseif os(iOS)
    @UIApplicationDelegateAdaptor
#endif
    private var appDelegate: iWebRTCMonitorAppDelegate
    
    var body: some Scene {
        MainScene()
    }
}

struct MainScene: Scene {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

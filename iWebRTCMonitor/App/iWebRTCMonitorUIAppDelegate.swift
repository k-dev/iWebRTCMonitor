//
//  iWebRTCMonitorUIAppDelegate.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 16.06.2026.
//

import Foundation
import UIKit

/// Receives incoming room URLs and posts their room identifiers to the UI.
class SceneDelegate: NSObject, UISceneDelegate {
    
    func handleURLContext(_ urlContext: UIOpenURLContext) {
        let sendingAppID = urlContext.options.sourceApplication
        let url = urlContext.url
        Log("source application = \(sendingAppID ?? "Unknown")")
        Log("url = \(url)")

        if let roomID = retrieveRoomID(from: url) {
            NotificationCenter.default.post(name: .joinRoomID, object: roomID)
        }
    }
    
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        Log(#function)
        if let urlContext = connectionOptions.urlContexts.first {
            handleURLContext(urlContext)
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Log(#function)
        if let urlContext = URLContexts.first {
            handleURLContext(urlContext)
        }
    }
}

extension iWebRTCMonitorAppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = connectingSceneSession.configuration
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

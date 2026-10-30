//
//  Helpers.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 19.06.2026.
//

import Foundation

func retrieveRoomID(from string: String) -> String? {
    if let url = URL(string: string) {
        return retrieveRoomID(from: url)
    }
    
    return nil
}

func retrieveRoomID(from url: URL) -> String? {
    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       components.host == "join",
       let queryItems = components.queryItems {
        for item in queryItems {
            if item.name == "roomID" {
                return item.value
            }
        }
    }
    
    return nil
}

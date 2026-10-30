//
//  Configuration.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 25.05.2026.
//

import Foundation

/// Reads static application configuration from the bundle.
struct Config {
    static let serverURLString: String = {
        return Bundle.main.object(forInfoDictionaryKey: "ServerURL") as? String ?? ""
    }()
    
    static let serverURL = URL(string: serverURLString)
}

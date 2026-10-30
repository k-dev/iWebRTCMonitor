//
//  SettingsView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 28.05.2026.
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var model: ContentViewModel
    
    var body: some View {
        Form {
            Section("Signaling Server Address") {
                TextField("URL", text: $model.serverAddress)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif
            }
#if DEBUG
            Toggle("Show Overlay", isOn: $model.showDebugOverlay)
#endif
        }
    }
}

#Preview {
    SettingsView()
}

//
//  ContentView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 09.05.2026.
//

import Combine
import SwiftUI

struct ContentView: View {
    @StateObject var model = ContentViewModel()
    
    var body: some View {
        ZStack {
            NavigationStack(path: $model.path) {
                RoleSelectionView()
                    .environmentObject(model)
            }
#if DEBUG
            .environment(\.isShowingDebugOverlay, model.showDebugOverlay)
#endif
#if DEBUG
            if model.showDebugOverlay {
                VStack {
                    Spacer()
                    LogBottomOverlay(
                        serverAddress: model.serverAddress,
                        dataSource: model.logs) {
                            LogBottomRowView(entry: $0)
                        }
                }
                .padding()
            }
#endif
        }
    }
}

#Preview {
    ContentView()
}

//
//  ViewerView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 24.05.2026.
//

import SwiftUI

struct ViewerView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isShowingDebugOverlay) private var showingGlobalDebugOverlay
    @StateObject var model: ViewerViewModel
    
    let dateFormat: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    var body: some View {
        VScrollView {
            ZStack {
                if model.videoTrack != nil {
                    RTCView(videoTrack: model.videoTrack)
                }
                else {
                    VStack {
                        ProgressView()
                        Text("Waiting...")
                            .foregroundColor(.primary)
                            .shadow(color: .white.opacity(0.3), radius: 0, x: 0, y: 1)
                    }
                    .padding()
                    .background(.background)
                    .clipShape(.rect(cornerRadius: 20.0))
                    .shadow(radius: 9.0, y: 3)
                }
                
                VStack() {
                    Text("Room: \(model.roomID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("ViewerID: \(model.viewerID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
#if DEBUG
                    // Disable log helper in view
                    if !showingGlobalDebugOverlay && false {
                        LogBottomOverlay(
                            title: "VIEW Log",
                            serverAddress: model.urlString,
                            dataSource: model.stateRecords
                        ) { record in
                            Text(dateFormat.string(from: record.time) + ": " + record.message)
                                .padding(.horizontal, 12)
                        }
                    }
#endif
                }
                .padding()
            }
        }
        .background(Color.yellow.opacity(0.7))
        .task(priority: .background) {
            if model.state == .initial || model.state == .failed {
                Log(level: .debug, "task Once")
                Task.detached {
                    await model.setup()
                }
            }
            Log(level: .debug, "task every show \(Unmanaged.passUnretained(model).toOpaque())")
        }
        .navigationTitle(model.viewTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .refreshable {
            Log(level: .debug, "refreshed")
        }
    }
}

#Preview {
    ViewerView(model: ViewerViewModel(roomID: "preview", urlString: "http://127.0.0.1"))
}

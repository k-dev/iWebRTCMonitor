//
//  RoleSelectionView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 18.06.2026.
//

import SwiftUI

/// Implements main screen UI with selection of client roles:
///  Camera (creates "Room" via RoomViewModel)
///  Viewer (receiver camera stream)
/// And handles app Settings.
struct RoleSelectionView: View {

    @EnvironmentObject var model: ContentViewModel
    
    @State private var settingsPresented = false
    
    var body: some View {
        VStack(spacing: 32) {

            NavigationLink(destination: {
                CameraView(model: RoomViewModel(roomID: model.roomID,
                                                urlString: model.serverAddress,
                                                role: .monitor,
                                                permissions: .forCameraScreen()))
            }) {
                HStack {
                    Text("Camera")
                        .controlSize(.large)
                }
//                    .modifier(CapsuleLinkStyle())
            }
            .controlSize(.large)
            .buttonStyle(CapsuleButtonLikeStyle())
            .accessibilityIdentifier("lobby.camera")
            
            Button("Viewer") {
                model.path.append(ContentNavigation.Main.roomSelection)
            }
            .controlSize(.large)
            .buttonStyle(CapsuleButtonLikeStyle())
        }
        .navigationDestination(for: ContentNavigation.Main.self) { path in
            switch path {
            case .roomSelection:
                RoomsView().environmentObject(model)
            }
        }
        .navigationTitle("Lobby")
        .padding()
        .toolbar { settingsButton }
    }
    
    var settingsButton: some View {
        Button("Settings") { settingsPresented.toggle() }
            .sheet(isPresented: $settingsPresented) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(model)
                        .navigationTitle("Settings")
#if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
                        .padding()
#endif
                        .toolbar {
                            Button("Done") {
                                settingsPresented.toggle()
                                Log(level: .status, "Server address:", model.serverAddress)
                            }
                        }
                }
            }
    }
}

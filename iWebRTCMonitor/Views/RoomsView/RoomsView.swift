//
//  RoomsView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 01.06.2026.
//

import SwiftUI

struct SelectionRow: View {

    let room: ViewerRecentRoom

    var body: some View {
        HStack {
            Text(room.id)
            Spacer()
        }
    }
}

struct RoomsView: View {
    
    @EnvironmentObject var model: ContentViewModel

    @State private var roomID: String = ""
    @State private var connectToShown = false
    @State private var detailsShown = false
    @State private var qrScannerShown = false
    
    var body: some View {
        VStack {
            Spacer()

            Button("Connect to") {
                connectToShown.toggle()
            }
            .sheet(isPresented: $connectToShown, onDismiss: {
                if !roomID.isEmpty {
                    addNewRoomID(roomID)
                    roomID = ""
                }
            }) {
                NavigationStack {
                    Form {
                        Button("Scan QR Code") {
                            connectToShown = false
                            qrScannerShown = true
                        }
                        Section("or enter Room ID manually") {
                            TextField("Room ID", text: $roomID)
                                .autocorrectionDisabled()
                        }
                    }
#if os(macOS)
                    .padding()
#endif
                    .toolbar {
                        Button("Done") {
                            if !isRoomIDCorrect(roomID) {
                                roomID = ""
                            }
                            connectToShown.toggle()
                        }
                    }
                }
            }
            
            List(model.recentRooms) { room in
                SelectionRow(room: room)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.path.append(ContentNavigation.RoomSelection.room(id: room.id))
                    }
            }
            .navigationDestination(for: ContentNavigation.RoomSelection.self) { path in
                if case let .room(roomID) = path {
                    ViewerView(model: ViewerViewModel(roomID: roomID, urlString: model.serverAddress))
                }
            }
            
            Spacer()
        }
        .sheet(isPresented: $qrScannerShown) {
            NavigationStack {
                QRScannerView { qrString in
                    Log(level: .debug, qrString)
                    if let qrID = retrieveRoomID(from: qrString) {
                        qrScannerShown = false
                        addNewRoomID(qrID)
                    }
                }
                .background(.black)
                .frame(minHeight: 300)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            qrScannerShown = false
                        }
                    }
                }
                .ignoresSafeArea(edges: [ .bottom ])
            }
        }
    }
    
    func addNewRoomID(_ roomID: String) {
        let recentRoom = ViewerRecentRoom(id: roomID)
        _ = model.addRecentRoom(recentRoom)
        model.path.append(ContentNavigation.RoomSelection.room(id: roomID))
    }
    
    func isRoomIDCorrect(_ roomID: String) -> Bool {
        // TODO: Check availability
        return !roomID.isEmpty
    }
}

//
//  CameraView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 27.05.2026.
//

import SwiftUI
import WebRTC

struct CameraView: View {
    
    @Environment(\.isShowingDebugOverlay) private var showingGlobalDebugOverlay
    @StateObject var model: RoomViewModel
    @State var showingPopover: Bool = false
    @State var aspectRatio = 3.0/4.0
    
    @Namespace private var cameraGroupNamespace
    
    let dateFormat: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "H:mm:ss.SSS"
        return df
    }()
    
    private func qrCodeButton(_ data: Data) -> some View {
        Button("QRCode") {
            showingPopover.toggle()
        }
        .accessibilityIdentifier("camera.qrCode")
        .popover(isPresented: $showingPopover) {
            NavigationStack {
                QRCodeView(qrData: data)
                    .toolbar {
                        ToolbarItem() { //placement: .topBarTrailing
                            Button("Done") {
                                showingPopover.toggle()
                            }
                        }
                    }
                    .padding()
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.orange.ignoresSafeArea()

            if let failure = model.permissionFailure {
                VStack(spacing: 16) {
                    Image(systemName: failure.resource == .camera ? "video.slash" : "mic.slash")
                        .font(.largeTitle)
                    Text(failure.title)
                        .font(.headline)
                        .accessibilityIdentifier("camera.permission.title")
                    Text(failure.message)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("camera.permission.message")
                    Button("Try Again") {
                        Task { await model.setup() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("camera.permission.retry")
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
            else if let localTrack = model.localVideoTrack {
                RTCView(videoTrack: localTrack) { size in
                    aspectRatio = size.width / size.height
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    HStack {
                        Spacer()
                        Button {
                            model.switchCamera()
                        } label: {
                            Text("Switch")
                        }
                        .tint(.green)
                        .padding([.top, .bottom], 4.0)
                        Spacer()
                    }
                    .background(.black.opacity(0.5))
                }
                .cornerRadius(12)
                .shadow(radius: 10)
                .transition(.opacity)
                .padding([.leading, .trailing], 20)
                .padding([.top, .bottom], 60)
            }
            else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(maxWidth: 200, maxHeight: 200)
                    ProgressView().colorInvert()
                        .accessibilityIdentifier("camera.loading")
                }
            }
            
            VStack() {
                Text("Room: \(model.roomID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Log(level: .status, "RoomID is copied to clipboard.")
#if os(iOS)
                        UIPasteboard.general.string = model.roomID
#elseif os(macOS)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(model.roomID, forType: .string)
#endif
                    }

                Spacer()
#if DEBUG
                // Disable log helper in view
                if !showingGlobalDebugOverlay && false {
                    LogBottomOverlay(
                        title: "CAM Log",
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
        .task {
            await model.setup()
        }
        .navigationTitle(model.viewTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if model.permissionFailure == nil, model.localVideoTrack != nil,
               let data = model.roomIDQuery.data(using: .ascii) {
                qrCodeButton(data)
            }
        }
    }
}

#Preview {
    CameraView(model: RoomViewModel(roomID: "", urlString: "http://127.0.0.1", role: .monitor))
}

//
//  DebugOverlay.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 31.05.2026.
//

import SwiftUI

private struct HeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Overlay view to show logs in app for better debugging.
struct LogBottomOverlay<T, RowContent: View>: View where T: LogRowRepresentable {
        
    // Quick stats shown even when collapsed
    var title = "DEV Log"
    var buildVersion: String? = nil
    var serverAddress: String? = nil
    var extraValues: [String: String] = [:]

    // Log entries fed from outside (e.g. via @StateObject logger)
    var dataSource: [T]
    @State private var isExpanded = false
    @State private var isChevronUpside = false
    
    var logRowView: (T) -> RowContent

    // Heights
    @State private var headerHeight: CGFloat = 31
    private let expandedHeight:  CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            // ─ Header (always visible) ─
            headerRow
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        isExpanded.toggle()
                    }
                    isChevronUpside.toggle()
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HeaderHeightKey.self, value: geo.size.height)
                })
                .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
            
            // ─ Line/Divider ─
            Line()
                .stroke(.green.opacity(0.35), style: StrokeStyle(lineWidth: 1.0))
                .frame(height: 1.0)
//            PixelLine(color: .green.opacity(0.35))

            // ─ Expanded content ─
            if isExpanded {
                logTable.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.black.opacity(0.88))
        .clipShape(
            RoundedRectangle(cornerRadius: 20)
        )
        .background(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.green)
    }

    // MARK: Header

    private var headerRow: some View {
        VStack {
            HStack(spacing: 12) {
                // Chevron indicator
                Image(systemName: isChevronUpside ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green.opacity(0.7))
                
                Text("⚙ " + title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                
                Spacer(minLength: 0)
                
                // Quick-stat chips
                if let buildVersion {
                    statChip("v\(buildVersion)")
                }
                if let serverAddress {
                    statChip(serverAddress.uppercased())//, accent: environment == "prod" ? .red : .cyan)
                }
                
                ForEach(Array(extraValues.keys.sorted()), id: \.self) { key in
                    statChip("\(key):\(extraValues[key] ?? "")")
                }
                
                // Log count badge
                if !dataSource.isEmpty {
                    Text("\(dataSource.count)")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding([.top, .bottom], 8)
    }

    private func statChip(_ text: String, accent: Color = .green) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(accent.opacity(0.12))
            .foregroundStyle(accent.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(accent.opacity(0.3), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Log Table

    private var logTableContent: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(dataSource) { entry in
                    logRowView(entry)
                        .id(entry.id)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: expandedHeight - headerHeight)
    }
    
    private var logTable: some View {
        ScrollViewReader { proxy in
            if #available(iOS 17.0, *) {
                logTableContent
                    .onChange(of: dataSource.count) {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
            }
            else {
                logTableContent
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = dataSource.last else { return }
        
        if animated {
            withAnimation(.default) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            // macOS and iOS rendering engine pipeline requires a brief deferral
            // on initial mount so layout geometry finishes calculating first.
            DispatchQueue.main.async {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var dataSource: [DebugLogEntry] = [
            .init(timestamp: .now - 120, level: .info,  message: "App launched"),
            .init(timestamp: .now - 90,  level: .info,  message: "Auth token refreshed"),
            .init(timestamp: .now - 60,  level: .warn,  message: "Cache miss for key: user_profile"),
            .init(timestamp: .now - 30,  level: .error, message: "Network request failed: /api/v2/feed – 503"),
            .init(timestamp: .now - 10,  level: .info,  message: "View appeared: HomeView"),
            .init(timestamp: .now,       level: .warn,  message: "Memory pressure: moderate"),
        ]

        var body: some View {
            ZStack(alignment: .top) {
                // Your app content behind
                LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                Text("App Content Here")
                    .foregroundStyle(.white)
                    .padding(.top, 120)

                // Overlay pinned to top
                VStack {
                    LogBottomOverlay(
                        buildVersion: "1.4.2",
                        serverAddress: "staging",
                        extraValues: ["fps": "59", "uid": "u_8a2f"],
                        dataSource: dataSource
                    ) { entry in
                        LogBottomRowView(entry: entry)
                    }
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }

    return PreviewWrapper()
}

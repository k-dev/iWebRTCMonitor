//
//  CapsuleButtonStyle.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 18.06.2026.
//

import SwiftUI

struct CapsuleLinkStyle: ViewModifier {
    @State private var hovering = false
    @State private var pressing = false
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(GeometryReader { geometry in
                Color.clear.task {
                    size = geometry.size
                }
                if hovering {
                    Color.gray.opacity(0.3).clipShape(.rect(cornerRadius: geometry.size.height / 2.0))
                }
                else {
                    Color.gray.opacity(0.2).clipShape(.rect(cornerRadius: geometry.size.height / 2.0))
                }
            })
            .contentShape(.rect(cornerRadius: size.height / 2.0))
            .onHover { hovering = $0 }
    }
}

struct CapsuleButtonLikeStyle: ButtonStyle {
    @State private var hovering = false
    @State var size: CGSize = .zero
    
    func compatibleBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(content: {
                if configuration.isPressed {
                    Color.gray.opacity(0.4).clipShape(.rect(cornerRadius: size.height / 2.0))
                }
                else if hovering {
                    Color.gray.opacity(0.3).clipShape(.rect(cornerRadius: size.height / 2.0))
                }
                else {
                    Color.gray.opacity(0.2).clipShape(.rect(cornerRadius: size.height / 2.0))
                }
            })
            .contentShape(.rect(cornerRadius: size.height / 2.0))
            .onHover { hovering = $0 }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onGeometryChange(for: CGSize.self) { proxy in
                return proxy.size
            } action: { newValue in
                size = newValue
            }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 17.0, *) {
            compatibleBody(configuration: configuration)
                .onChange(of: configuration.isPressed, { oldValue, newValue in
                    hovering = hovering && !newValue
                })
        } else {
            compatibleBody(configuration: configuration)
        }
    }
}

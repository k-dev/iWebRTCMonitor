//
//  VScrollView.swift
//  iWebRTCMonitor
//
//  Created on 27.05.2026.
//
//  Source: https://stackoverflow.com/questions/58122998/vertical-centering-content-inside-scrollview
//

import SwiftUI

struct VScrollView<Content>: View where Content: View {
    
    @ViewBuilder let content: Content
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                content
                    .frame(width: geometry.size.width)
                    .frame(minHeight: geometry.size.height)
            }
        }
    }
}

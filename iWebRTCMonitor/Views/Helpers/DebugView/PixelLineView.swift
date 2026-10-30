//
//  PixelLineView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 01.07.2026.
//

import SwiftUI

struct Line: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct PixelLine: View {

    @Environment(\.displayScale) var displayScale
    var color: Color

    var body: some View {
        color
            .frame(height: 1.0 / displayScale)
    }
}

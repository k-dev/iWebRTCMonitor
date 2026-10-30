//
//  LogBottomRow.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 18.06.2026.
//

import SwiftUI

protocol LogRowRepresentable: Identifiable {
}

struct DebugLogEntry: LogRowRepresentable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel {
        case debug
        case verbose
        case info
        case warn
        case error
    }
}

extension DebugLogEntry.LogLevel {

    static let debugSymbol      = "ladybug"
    static let verboseSymbol    = "book.and.wrench"
    static let infoSymbol       = "info.circle"
    static let warningSymbol    = "exclamationmark.triangle.fill"
    static let errorSymbol      = "exclamationmark.octagon.fill"
    
    var color: Color {
        switch self {
        case .debug:   return .green
        case .verbose: return .gray
        case .info:    return .cyan
        case .warn:    return .yellow
        case .error:   return .red
        }
    }
    
    var tag: String {
        switch self {
        case .debug:   return "D"
        case .verbose: return "V"
        case .info:    return "I"
        case .warn:    return "W"
        case .error:   return "E"
        }
    }
    
    var symbolName: String {
        switch self {
        case .debug:   return Self.debugSymbol
        case .verbose: return Self.verboseSymbol
        case .info:    return Self.infoSymbol
        case .warn:    return Self.warningSymbol
        case .error:   return Self.errorSymbol
        }
    }
}

struct LogBottomRowView: View {
    
    static let timeDF: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SS"
        return df
    }()
    
    let entry: DebugLogEntry
    
    var body: some View {
        Text(attributedContentString())
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(
                entry.level == .error
                ? Color.red.opacity(0.07)
                : Color.clear
            )
    }
    
    func columnsView() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Timestamp
            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                .foregroundStyle(.white.opacity(0.5))
                .frame(alignment: .leading)
            
            // Level badge
            Text(entry.level.tag)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(entry.level.color)
            
            // Message
            Text(entry.message)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    func attributedContentString() -> AttributedString {

        var timeStr = AttributedString(Self.timeDF.string(from: entry.timestamp))
        timeStr.foregroundColor = .white.opacity(0.5)

        var levelStr = AttributedString(entry.level.tag)
        levelStr.font = .system(size: 10, weight: .heavy, design: .monospaced)
        levelStr.foregroundColor = entry.level.color.opacity(0.6)
        
        var messageStr = AttributedString(entry.message)
        messageStr.foregroundColor = .green.opacity(0.8)
        
        return timeStr + " " + levelStr + " " + messageStr
    }
    
    var logRowView: some View {

        var timeStr = AttributedString(Self.timeDF.string(from: entry.timestamp))
        timeStr.foregroundColor = .white.opacity(0.5)
        
        var messageStr = AttributedString(entry.message)
        messageStr.foregroundColor = .green.opacity(0.8)
        
        return Text(timeStr + " ")
        + Text(Image(systemName: entry.level.symbolName))
            .fontDesign(.monospaced)
            .foregroundColor(entry.level.color)
        + Text(" " + messageStr)
    }
    
}

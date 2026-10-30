//
//  ContentViewModel.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 28.05.2026.
//

import Combine
import Foundation
import SwiftUI

enum ContentNavigation {

    enum Main {
        case roomSelection
    }

    enum RoomSelection: Hashable {
        case room(id: String)
    }
}

struct ViewerRecentRoom: Identifiable, Hashable {
    let id: String
}

/// Holds navigation, settings, and debug-log state for the root SwiftUI view.
///
/// `ContentView` creates and owns this object. Notification and logger callbacks transfer
/// published-state updates to the main actor.
@MainActor
class ContentViewModel: ObservableObject {

    let roomID: String = UUID().uuidString

    @Published var path = NavigationPath()
    @Published var serverAddress = Config.serverURLString
    @Published var recentRooms: [ViewerRecentRoom] = []
    @Published var openURLroomID: String?

#if DEBUG
    @Published var showDebugOverlay: Bool
    @Published var logs: [DebugLogEntry] = []
#endif
    
    init () {
#if DEBUG
        showDebugOverlay = true
        Logger.default.inAppLogHandler = self.logHandler
#endif
        NotificationCenter.default.addObserver(forName: .joinRoomID,
                                               object: nil,
                                               queue: nil) { [weak self] note in
            if let roomID = note.object as? String {
                DispatchQueue.main.async {
                    guard let self else { return }
                    _ = self.addRecentRoom(ViewerRecentRoom(id: roomID))
                    self.path.removeLast(self.path.count)
                    Log(level: .debug, self.path)
                    self.path.append(ContentNavigation.Main.roomSelection)
                    Log(level: .debug, self.path)
                    self.path.append(ContentNavigation.RoomSelection.room(id: roomID))
                    Log(level: .debug, self.path)
                }
            }
        }
    }
    
    func addRecentRoom(_ room: ViewerRecentRoom) -> Bool {
        guard !Set(recentRooms).contains(room) else {
            return false
        }
                
        recentRooms.append(room)
        return true
    }
    
#if DEBUG
    private func logHandler(timestamp: Date, category: Logger.Category, level: Logger.Level, message: String) {
        Task.detached { @MainActor [weak self] in
            self?.logs.append(DebugLogEntry(timestamp: timestamp, level: level.debugLogEntryLevel, message: message))
        }
    }
#endif
}

extension Logger.Level {
    var debugLogEntryLevel: DebugLogEntry.LogLevel {
        switch self {
        case .debug: return .debug
        case .verbose: return .verbose
        case .status: return .info
        case .warning: return .warn
        case .error: return .error
        }
    }
}

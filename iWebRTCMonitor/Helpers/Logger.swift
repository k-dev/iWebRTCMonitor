//
//  Logger.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 19.06.2026.
//

import Foundation
import os

func Log(category: Logger.Category = .default, level: Logger.Level = .status, format: StaticString, _ args: Any...) {
    Logger.default.log(category: category, level: level, format: format, args)
}

func Log(category: Logger.Category = .default, level: Logger.Level = .status, _ args: Any..., separator: String = " ") {
    Logger.default.log(category: category, level: level, args.map({"\($0)"}).joined(separator: separator))
}

/// Writes diagnostic messages to configured outputs.
///
/// `Logger.default` owns the process-wide logger. The logger queue calls the
/// optional in-app handler. That handler must transfer UI updates to the main
/// actor. Configuration fields have no documented synchronization contract.
class Logger: @unchecked Sendable {
    
    /// Identifies a log source. Declare module categories in extensions.
    /// A nil level uses the logger's minimum level.
    struct Category {
        let rawValue: String
        let logLevel: Level?
        let prefix: String?
    }

    enum Level: Int {
        case debug
        case verbose
        case status
        case warning
        case error
    }
    
    struct Output: OptionSet {
        let rawValue: Int
        static let print = Output(rawValue: 1 << 0)
        static let osLog = Output(rawValue: 1 << 1)
        static let nsLog = Output(rawValue: 1 << 2)
        static let inApp = Output(rawValue: 1 << 3)
    }
    
    private let subsystem = Bundle.main.bundleIdentifier ?? "no.bundleId"
    private let logQueue = DispatchQueue(label: "logger.queue", qos: .background)

#if DEBUG
    private(set) var level: Level = .debug
#else
    private(set) var level: Level = .status
#endif

    private(set) var output: Output = [ .print, .inApp ]
    
    var inAppLogHandler: ((Date, Category, Level, String) -> Void)?
    
    static let `default` = Logger()
    
    func log(timestamp: Date = Date(), category: Category, level: Level, _ msg: String) {
        if level >= (category.logLevel ?? self.level) {
            self.logOut(timestamp: timestamp, category: category, level: level, to: self.output, message: msg)
        }
    }
    
    func log(timestamp: Date = Date(), category: Category, level: Level, format: StaticString, _ args: [Any] = []) {
        self._log(timestamp: timestamp, category: category, level: level, format: format, args)
    }
    
    private func _log(timestamp: Date, category: Category, level: Level, format: StaticString, _ args: [Any] = []) {
        let minLogLevel = category.logLevel ?? self.level
        guard level >= minLogLevel else { return }

        guard args.count > 0 else {
            self.logOut(timestamp: timestamp, category: category, level: level, to: output, message: String(format))
            return
        }
        
        var cvargs: [CVarArg] = []
        for item in args {
            if let cvarg = item as? CVarArg {
                cvargs.append(cvarg)
            }
            else {
                cvargs.append("<unknown>" as CVarArg)
            }
        }
        
        let string = String(format: String(describing: format), arguments: cvargs)
        self.logOut(timestamp: timestamp, category: category, level: level, to: output, message: string)
    }
    
    private func logOut(timestamp: Date, category: Category, level: Level, to output: Output, message: String) {
        let text: String
        if let prefix = category.prefix {
            text = "[\(prefix)] \(message)"
        }
        else {
            text = message
        }

        if output.contains(.print) {
            print(text)
        }
        if output.contains(.nsLog) {
            NSLog("%@", text)
        }
        if output.contains(.osLog) {
            let log = OSLog(subsystem: subsystem, category: category.rawValue)
            os_log(level.osLogType, log: log, "%{public}@", message)
        }
        if output.contains(.inApp) {
            logInApp(timestamp: timestamp, category: category, level: level, message: message)
        }
    }
    
    private func logInApp(timestamp: Date, category: Category, level: Level, message: String) {
        logQueue.async { [weak self] in
            self?.inAppLogHandler?(timestamp, category, level, message)
        }
    }
}

extension Logger.Level {
    
    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .verbose:
            return .info
        case .status:
            return .default
        case .warning:
            return .error
        case .error:
            return .fault
        }
    }
}

extension Logger.Level: Comparable {

    static func < (lhs: Logger.Level, rhs: Logger.Level) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

extension String {

    init(_ staticString: StaticString) {
        self = staticString.withUTF8Buffer {
            String(decoding: $0, as: UTF8.self)
        }
    }
}

extension Logger.Category: RawRepresentable, Hashable {

    init(rawValue: String) {
        self.init(rawValue: rawValue, logLevel: nil, prefix: nil)
    }
}

extension Logger.Category {

    static let `default` = Self(rawValue: "default")
}

import Foundation
import Testing
import XCTest
@testable import iWebRTCMonitor

private struct LogEntry: Equatable {
    var category: Logger.Category = .default
    let level: Logger.Level
    let message: String
}

private final class LogEntries: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [LogEntry] = []

    func append(category: Logger.Category, level: Logger.Level, message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(LogEntry(category: category, level: level, message: message))
    }

    func snapshot() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LoggerTests {
    // The iOS host app installs its own Logger.default handler during startup.
    // Each test owns a logger so app lifecycle events cannot replace its handler.
    // Logger delivers through a weak reference, so keep it alive until delivery completes.
    private func wait(for expectation: XCTestExpectation, keeping logger: Logger) async throws {
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        withExtendedLifetime(logger) {}
        try #require(result == .completed, "The logger did not deliver all expected messages")
    }

    @Test
    func existingLoggingCallsDeliverFormattedMessagesAndLevels() async throws {
        let token = UUID().uuidString
        let entries = LogEntries()
        let delivered = XCTestExpectation(description: "Existing log calls deliver messages")
        delivered.expectedFulfillmentCount = 4
        let logger = Logger()

        let plainMessage = "\(token)|plain"
        let formattedMessage = "logger-test-format-7"
        let defaultLevelMessage = "\(token) default-level"
        let defaultFormatMessage = "logger-test-status-9"
        logger.inAppLogHandler = { _, category, level, message in
            guard [plainMessage, formattedMessage, defaultLevelMessage, defaultFormatMessage].contains(message) else { return }
            entries.append(category: category, level: level, message: message)
            delivered.fulfill()
        }

        Log(logger: logger, level: .warning, token, "plain", separator: "|")
        Log(logger: logger, level: .error, format: "logger-test-format-%d", 7)
        Log(logger: logger, token, "default-level")
        Log(logger: logger, format: "logger-test-status-%d", 9)

        try await wait(for: delivered, keeping: logger)
        #expect(entries.snapshot() == [
            LogEntry(level: .warning, message: plainMessage),
            LogEntry(level: .error, message: formattedMessage),
            LogEntry(level: .status, message: defaultLevelMessage),
            LogEntry(level: .status, message: defaultFormatMessage)
        ])
    }

    @Test
    func defaultInAppDestinationAndSeverityFilteringRemainActive() async throws {
        let logger = Logger()
        #expect(logger.output.contains(.inApp))

        let token = UUID().uuidString
        let levels: [Logger.Level] = [.debug, .verbose, .status, .warning, .error]
        let expectedLevels = levels.filter { $0 >= logger.level }
        let entries = LogEntries()
        let delivered = XCTestExpectation(description: "Accepted levels reach the in-app destination")
        delivered.expectedFulfillmentCount = expectedLevels.count

        logger.inAppLogHandler = { _, category, level, message in
            guard message.hasPrefix(token) else { return }
            entries.append(category: category, level: level, message: message)
            delivered.fulfill()
        }

        for level in levels {
            Log(logger: logger, level: level, "\(token)-\(level.rawValue)")
        }

        try await wait(for: delivered, keeping: logger)
        #expect(entries.snapshot().map(\.level) == expectedLevels)
    }

    @Test
    func concurrentLoggingDeliversEveryAcceptedMessage() async throws {
        let logger = Logger()
        let count = 64
        let token = UUID().uuidString
        let entries = LogEntries()
        let delivered = XCTestExpectation(description: "Concurrent messages reach the in-app destination")
        delivered.expectedFulfillmentCount = count

        logger.inAppLogHandler = { _, category, level, message in
            guard level == .error, message.hasPrefix(token) else { return }
            entries.append(category: category, level: level, message: message)
            delivered.fulfill()
        }

        DispatchQueue.concurrentPerform(iterations: count) { index in
            let category: Logger.Category = index.isMultiple(of: 2) ? .default : .loggerTests
            Log(logger: logger, category: category, level: .error, "\(token)-\(index)")
        }

        try await wait(for: delivered, keeping: logger)
        let received = Set(entries.snapshot().map(\.message))
        let expected = Set((0..<count).map { "\(token)-\($0)" })
        #expect(received == expected)
        #expect(entries.snapshot().count == count)
        for index in 0..<count {
            let category: Logger.Category = index.isMultiple(of: 2) ? .default : .loggerTests
            #expect(entries.snapshot().contains(LogEntry(category: category, level: .error, message: "\(token)-\(index)")))
        }
    }

    @Test
    func moduleCategoryReachesBothLoggingOverloads() async throws {
        let logger = Logger()
        let entries = LogEntries()
        let marker = UUID().uuidString
        let delivered = XCTestExpectation(description: "Category messages precede the marker")
        logger.inAppLogHandler = { _, category, level, message in
            if message == marker { delivered.fulfill() }
            else if category == .loggerTests {
                entries.append(category: category, level: level, message: message)
            }
        }

        Log(logger: logger, category: .loggerTests, level: .warning, "camera", 7, separator: "|")
        Log(logger: logger, category: .loggerTests, level: .error, format: "camera-%d", 8)
        Log(logger: logger, category: .loggerTests, level: .status, format: "camera-ready")
        Log(logger: logger, level: .error, marker)
        try await wait(for: delivered, keeping: logger)

        #expect(entries.snapshot() == [
            LogEntry(category: .loggerTests, level: .warning, message: "camera|7"),
            LogEntry(category: .loggerTests, level: .error, message: "camera-8"),
            LogEntry(category: .loggerTests, level: .status, message: "camera-ready")
        ])
    }

    @Test(arguments: [Logger.Level.debug, .error])
    func categoryThresholdOverridesGlobalLevel(threshold: Logger.Level) async throws {
        let logger = Logger()
        let category = Logger.Category(rawValue: "threshold-test", logLevel: threshold, prefix: "threshold")
        let entries = LogEntries()
        let marker = UUID().uuidString
        let delivered = XCTestExpectation(description: "The marker follows all filtered messages")
        logger.inAppLogHandler = { _, category, level, message in
            if message == marker { delivered.fulfill() }
            else { entries.append(category: category, level: level, message: message) }
        }
        let levels: [Logger.Level] = [.debug, .verbose, .status, .warning, .error]
        for level in levels {
            logger.log(category: category, level: level, "plain")
            logger.log(category: category, level: level, format: "value-%d", [7])
            logger.log(category: category, level: level, format: "literal")
        }
        logger.log(category: .default, level: .error, marker)
        try await wait(for: delivered, keeping: logger)

        let accepted: [Logger.Level] = threshold == .debug ? levels : [.error]
        #expect(entries.snapshot() == accepted.flatMap { level in
            ["plain", "value-7", "literal"].map {
                LogEntry(category: category, level: level, message: $0)
            }
        })
    }

    @Test
    func categoryWithoutThresholdUsesGlobalFilterAndPreservesDestinations() async throws {
        let logger = Logger()
        let originalOutput = logger.output
        #expect(originalOutput == [.print, .inApp])
        let category = Logger.Category(rawValue: "inherited-test")
        let entries = LogEntries()
        let marker = UUID().uuidString
        let delivered = XCTestExpectation(description: "The marker follows default and named messages")
        logger.inAppLogHandler = { _, category, level, message in
            if message == marker { delivered.fulfill() }
            else { entries.append(category: category, level: level, message: message) }
        }
        let levels: [Logger.Level] = [.debug, .verbose, .status, .warning, .error]
        for level in levels {
            logger.log(category: .default, level: level, "default")
            logger.log(category: category, level: level, "named")
        }
        logger.log(category: .default, level: .error, marker)
        try await wait(for: delivered, keeping: logger)

        #if DEBUG
        let accepted = levels
        #else
        let accepted: [Logger.Level] = [.status, .warning, .error]
        #endif
        #expect(entries.snapshot() == accepted.flatMap { level in
            [LogEntry(level: level, message: "default"),
             LogEntry(category: category, level: level, message: "named")]
        })
        #expect(logger.output == originalOutput)
    }
}

private extension Logger.Category {
    static let loggerTests = Self(rawValue: "logger-tests")
}

import XCTest

/// Exercises the real Camera screen with deterministic permission responses.
/// System permission dialogs and actual capture are intentionally outside these tests.
@MainActor
final class CapturePermissionsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openCamera(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_CAPTURE_PERMISSIONS"] = scenario
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let camera = app.buttons["lobby.camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 10))
        camera.tap()
        return app
    }

    private func assertFailure(_ app: XCUIApplication, resource: String, restricted: Bool = false,
                               file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts["camera.permission.title"]
        let expectedTitle = "\(resource) access required"
        guard waitForText(title, matching: NSPredicate(format: "label == %@ OR value == %@",
                                                       expectedTitle, expectedTitle),
                          expected: expectedTitle, file: file, line: line) else { return }
        let message = app.staticTexts["camera.permission.message"]
        let expectedMessage = restricted ? "restricted by system policy" : "Privacy & Security"
        guard waitForText(message, matching: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                                                         expectedMessage, expectedMessage),
                          expected: expectedMessage, file: file, line: line) else { return }
        XCTAssertTrue(app.buttons["camera.permission.retry"].isHittable, file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any)["camera.loading"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["camera.qrCode"].exists, file: file, line: line)
    }

    /// SwiftUI text may expose its content as label on iOS or value on macOS.
    /// Wait for the text as well as existence so retry can update an existing element.
    private func waitForText(_ element: XCUIElement, matching predicate: NSPredicate,
                             expected: String, file: StaticString, line: UInt) -> Bool {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Missing text element: \(element.debugDescription)", file: file, line: line)
            return false
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: 10) == .completed else {
            XCTFail("Expected \(expected.debugDescription); label=\(element.label.debugDescription), value=\(String(describing: element.value))",
                    file: file, line: line)
            return false
        }
        return true
    }

    func testCameraDenied() {
        assertFailure(openCamera(scenario: "camera-denied"), resource: "Camera")
    }

    func testMicrophoneDenied() {
        assertFailure(openCamera(scenario: "microphone-denied"), resource: "Microphone")
    }

    func testCameraRestricted() {
        assertFailure(openCamera(scenario: "camera-restricted"), resource: "Camera", restricted: true)
    }

    func testMicrophoneRestricted() {
        assertFailure(openCamera(scenario: "microphone-restricted"), resource: "Microphone", restricted: true)
    }

    func testRetryReflectsChangedPermissions() {
        let app = openCamera(scenario: "retry")
        assertFailure(app, resource: "Camera")
        // The fixture grants camera access on the next check, leaving microphone denied.
        app.buttons["camera.permission.retry"].tap()
        assertFailure(app, resource: "Microphone")
        let title = app.staticTexts["camera.permission.title"]
        XCTAssertNotEqual(title.label, "Camera access required")
        XCTAssertNotEqual(title.value as? String, "Camera access required")
    }
}

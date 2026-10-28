import XCTest

/// Walks the screens on demo data and saves a screenshot of each, so they can be looked at
/// without a Mac. Each one is attached to the result bundle and, when `SCREENSHOT_DIR` is set,
/// written straight to that folder as `<device>-<nn>-<name>.png` (scripts/collect_screenshots.py).
/// Add a step here for every new screen.
final class ScreenshotTests: XCTestCase {
    private var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Allow", "OK", "Don\u{2019}t Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    private func launch(appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-mockAPI",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", appearance == "dark" ? "Dark" : "Light",
        ]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: settle)
        let screenshot = XCUIScreen.main.screenshot()
        let fileName = "\(device)-\(name).png"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(fileName)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url)
        }
    }

    func testSignUpAndHome() {
        let app = launch()
        let demo = app.buttons["Try the demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        snap(app, "01-sign-in")

        demo.tap()
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.typeText("patdoe")
        snap(app, "02-username")
        app.buttons["Continue"].tap()

        let note = app.textFields["Write a note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        snap(app, "03-home-empty")
        note.tap()
        note.typeText("Call Pat at 555-0100")
        app.buttons["Add"].tap()
        snap(app, "04-home")

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        snap(app, "05-settings")
    }
}

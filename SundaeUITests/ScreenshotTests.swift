import XCTest

/// Walks every screen against the mock backend and saves a screenshot of each.
/// Screenshots are attached to the result bundle and, when `SCREENSHOT_DIR` is set,
/// written straight to that folder as `<device>-<name>.png`.
final class ScreenshotTests: XCTestCase {
    private var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(day: String, signedIn: Bool = true, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-mockAPI",
            "-debugDay", day,
            "-appearance", appearance,
            signedIn ? "-uiTestSignedIn" : "-uiTestSignedOut",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String, settle: TimeInterval = 1.2) {
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

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            // Regular width uses a sidebar instead of a tab bar.
            let sidebarButton = app.buttons[name].firstMatch
            if sidebarButton.waitForExistence(timeout: 5) { sidebarButton.tap() }
        }
    }

    func testOnboarding() {
        let app = launch(day: "weekday", signedIn: false)
        XCTAssertTrue(app.staticTexts["Sundae"].waitForExistence(timeout: 15))
        snap(app, "00-onboarding-welcome")
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["Sign in"].waitForExistence(timeout: 5))
        snap(app, "00-onboarding-signin")
    }

    func testWeekday() {
        let app = launch(day: "weekday")
        XCTAssertTrue(app.buttons["Shuffle"].waitForExistence(timeout: 15))
        snap(app, "01-weekday")
        app.buttons["Done"].tap()
        snap(app, "01-weekday-done", settle: 0.8)
    }

    func testWeekdayDark() {
        let app = launch(day: "weekday", appearance: "dark")
        XCTAssertTrue(app.buttons["Shuffle"].waitForExistence(timeout: 15))
        snap(app, "01-weekday-dark")
    }

    func testSunday() {
        let app = launch(day: "sunday")
        XCTAssertTrue(app.navigationBars["Sunday"].waitForExistence(timeout: 20))
        snap(app, "02-feed", settle: 2.5)

        // Open the first friend's profile from the feed header.
        let maya = app.buttons.containing(.staticText, identifier: "Maya Chen").firstMatch
        if maya.waitForExistence(timeout: 5) {
            maya.tap()
            snap(app, "03-profile-friend", settle: 2)
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }

        // Dump detail with comments.
        let comments = app.buttons["Comments"].firstMatch
        if comments.waitForExistence(timeout: 5) {
            comments.tap()
            snap(app, "04-dump-detail", settle: 2)
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }

        tab(app, "Search")
        snap(app, "05-search", settle: 2)

        tab(app, "Post")
        snap(app, "06-compose", settle: 2)

        tab(app, "Approvals")
        snap(app, "07-approvals", settle: 2)

        tab(app, "Profile")
        snap(app, "08-profile-own", settle: 2)

        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            snap(app, "09-settings", settle: 1.5)
        }
    }

    func testSundayDark() {
        let app = launch(day: "sunday", appearance: "dark")
        XCTAssertTrue(app.navigationBars["Sunday"].waitForExistence(timeout: 20))
        snap(app, "02-feed-dark", settle: 2.5)
    }
}

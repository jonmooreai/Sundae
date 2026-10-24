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
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Allow", "Allow Full Access", "OK", "Don\u{2019}t Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
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
        let button = app.buttons["tab-\(name.lowercased())"].firstMatch
        if button.waitForExistence(timeout: 5) { button.tap() }
    }

    private func back(_ app: XCUIApplication) {
        let button = app.buttons["Back"].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
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

        // Sunday opens on the prompt.
        XCTAssertTrue(app.buttons["Pick your photos"].waitForExistence(timeout: 20))
        snap(app, "02-sunday-prompt", settle: 1.5)
        app.buttons["Pick your photos"].tap()

        // Pick: allow the library if asked, then switch to all photos (the simulator's samples are old).
        let allow = app.buttons["Show my photos"].firstMatch
        if allow.waitForExistence(timeout: 4) {
            allow.tap()
            Thread.sleep(forTimeInterval: 1.5)
            app.navigationBars.firstMatch.tap()   // gives the interruption monitor a chance to answer the system alert
        }
        let all = app.buttons["All photos"].firstMatch
        if all.waitForExistence(timeout: 8) { all.tap() }
        snap(app, "06-compose-pick", settle: 3)

        let cells = app.buttons.matching(identifier: "library-cell")
        let pickCount = min(4, cells.count)
        for i in 0..<pickCount { cells.element(boundBy: i).tap() }
        if pickCount > 0 {
            snap(app, "06-compose-pick-selected", settle: 1)
            app.buttons["flow-primary"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Arrange and tag"].waitForExistence(timeout: 30))
            snap(app, "06-compose-arrange", settle: 3)

            let tag = app.buttons["tag-friends"].firstMatch
            if tag.waitForExistence(timeout: 3) {
                tag.tap()
                snap(app, "06-compose-tag", settle: 2)
                let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'maya'")).firstMatch
                if first.waitForExistence(timeout: 3) { first.tap() }
                let done = app.buttons["Done"].firstMatch
                if done.waitForExistence(timeout: 3) { done.tap() }
            }

            app.buttons["flow-primary"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["How was your week?"].waitForExistence(timeout: 10))
            let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                if app.keyboards.count > 0 {
                    app.typeText("Bikes, a very long lunch, and the first cold morning.")
                }
            }
            snap(app, "06-compose-caption", settle: 1.5)
            app.buttons["flow-primary"].firstMatch.tap()
            XCTAssertTrue(app.buttons["See the feed"].waitForExistence(timeout: 20))
            snap(app, "06-compose-posted", settle: 2.5)
            app.buttons["See the feed"].tap()
        } else {
            // Nothing to pick on this simulator: close the flow and carry on.
            let close = app.buttons["Close"].firstMatch
            if close.waitForExistence(timeout: 3) { close.tap() }
        }

        XCTAssertTrue(app.staticTexts["Sunday"].waitForExistence(timeout: 20))
        snap(app, "02-feed", settle: 5)

        // Open the first friend's profile from a feed header.
        let author = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'author-'")).firstMatch
        if author.waitForExistence(timeout: 8) {
            author.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            snap(app, "03-profile-friend", settle: 5)
            back(app)
        }

        // Dump detail with comments.
        let comments = app.buttons["Comments"].firstMatch
        if comments.waitForExistence(timeout: 5) {
            comments.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            snap(app, "04-dump-detail", settle: 4)
            back(app)
        }

        tab(app, "Approvals")
        snap(app, "07-approvals", settle: 4)

        tab(app, "Profile")
        snap(app, "08-profile-own", settle: 5)

        let settings = app.descendants(matching: .any)["profile-settings"].firstMatch
        if settings.waitForExistence(timeout: 8) {
            settings.tap()
            snap(app, "09-settings", settle: 1.5)
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 3) { done.tap() }
        }

        // Last, because the search tab replaces the tab bar with a search field on iOS 26.
        tab(app, "Search")
        snap(app, "05-search", settle: 4)
    }

    func testSundayDark() {
        let app = launch(day: "sunday", appearance: "dark")
        let later = app.buttons["Show me the feed first"].firstMatch
        if later.waitForExistence(timeout: 20) {
            snap(app, "02-sunday-prompt-dark", settle: 1.5)
            later.tap()
        }
        XCTAssertTrue(app.staticTexts["Sunday"].waitForExistence(timeout: 20))
        snap(app, "02-feed-dark", settle: 5)
    }
}

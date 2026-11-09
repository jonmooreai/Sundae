import XCTest

/// Walks every screen against the mock backend and saves a screenshot of each.
/// Screenshots are attached to the result bundle and, when `SCREENSHOT_DIR` is set,
/// written straight to that folder as `<device>-<name>.png`. The iPhone Duo's files start
/// with `Duo`, and the landscape run's with `DuoLandscape` (LandscapeScreenshotTests).
class ScreenshotTests: XCTestCase {
    /// Turned sideways for every screen. The landscape run overrides it.
    var landscape: Bool { false }

    private var device: String {
        let simulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        let base = simulator.contains("Duo") ? "Duo" : UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return landscape ? "\(base)Landscape" : base
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
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
        if name.hasPrefix("00-onboarding-intro-film") {
            // Once per run, for the record: how many displays the device shows, and the size of the
            // one the app is on. Only the main screen is photographed: asking a display that is off
            // for a picture can wait forever.
            print("[screens] \(device): \(XCUIScreen.screens.count) main \(screenshot.image.size) window \(app.windows.firstMatch.frame)")
        }
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
        // The film plays full screen; the title and Begin come in when it ends.
        let film = app.descendants(matching: .any)["A felt ice cream sundae, built scoop by scoop, with a cherry on top"].firstMatch
        XCTAssertTrue(film.waitForExistence(timeout: 15))
        snap(app, "00-onboarding-intro-film")
        // A tap skips the film to the finished sundae, where Begin appears.
        app.tap()
        XCTAssertTrue(app.buttons["Begin"].waitForExistence(timeout: 15))
        snap(app, "00-onboarding-intro")
        app.buttons["Begin"].tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
        snap(app, "00-onboarding-welcome")
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["Sign in"].waitForExistence(timeout: 5))
        snap(app, "00-onboarding-signin")
    }

    func testWeekday() {
        let app = launch(day: "weekday")
        XCTAssertTrue(app.buttons["Shuffle"].waitForExistence(timeout: 15))
        snap(app, "01-weekday")
        let save = app.buttons["Save"].firstMatch
        guard save.waitForExistence(timeout: 3) else {
            XCTFail("No Save button: the idea was already saved, so the launch did not start clean")
            return
        }
        save.tap()
        // The first Save slides up a short explainer; one shot of it, then one of the saved idea.
        snap(app, "01-weekday-saved-intro", settle: 1.2)
        for title in ["Got it", "Not now"] {
            let button = app.buttons[title].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }
        snap(app, "01-weekday-saved", settle: 0.8)
    }

    func testWeekdayDark() {
        let app = launch(day: "weekday", appearance: "dark")
        XCTAssertTrue(app.buttons["Shuffle"].waitForExistence(timeout: 15))
        snap(app, "01-weekday-dark")
    }

    func testSunday() {
        let app = launch(day: "sunday")

        // Sunday opens on the prompt. If the app never answers, a picture of whatever it shows.
        let prompt = app.buttons["Pick your photos"].waitForExistence(timeout: 20)
        if !prompt { snap(app, "02-sunday-prompt-missing", settle: 0) }
        XCTAssertTrue(prompt)
        snap(app, "02-sunday-prompt", settle: 1.5)
        app.buttons["Pick your photos"].tap()

        // Pick: allow the library if asked, then switch to all photos (the simulator's samples are old).
        let allow = app.buttons["Show my photos"].firstMatch
        if allow.waitForExistence(timeout: 4) {
            allow.tap()
            Thread.sleep(forTimeInterval: 1.5)
            // Any interaction lets the interruption monitor answer the system alert.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            Thread.sleep(forTimeInterval: 1)
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

            // The photo editor: open it, look at the crop and a slider, keep the change.
            let edit = app.buttons["edit-photo"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 5), "every photo has Edit")
            edit.tap()
            XCTAssertTrue(app.staticTexts["Edit photo"].waitForExistence(timeout: 15))
            let straighten = app.sliders["Straighten"].firstMatch
            XCTAssertTrue(straighten.waitForExistence(timeout: 5), "fine rotation in the crop tool")
            straighten.adjust(toNormalizedSliderPosition: 0.65)
            snap(app, "06-compose-edit-crop", settle: 2)
            // Held on the photo, the before shows.
            let canvas = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'The photo.'")).firstMatch
            if canvas.waitForExistence(timeout: 3) { canvas.press(forDuration: 1.0) }
            XCTAssertFalse(app.buttons["Start over"].exists, "no Start over")
            let warmth = app.buttons["Warmth"].firstMatch
            if warmth.waitForExistence(timeout: 3) {
                warmth.tap()
                let slider = app.sliders["Warmth"].firstMatch
                if slider.waitForExistence(timeout: 3) { slider.adjust(toNormalizedSliderPosition: 0.8) }
                snap(app, "06-compose-edit-warmth", settle: 1.5)
            }
            app.buttons["Done"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Arrange and tag"].waitForExistence(timeout: 20), "back to arranging once kept")

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
            // Nothing to pick on this simulator: leave the flow and carry on to the feed.
            let close = app.buttons["Close"].firstMatch
            if close.waitForExistence(timeout: 2) {
                close.tap()
            } else {
                back(app)
                let later = app.buttons["Show me the feed first"].firstMatch
                if later.waitForExistence(timeout: 3) { later.tap() }
            }
        }

        XCTAssertTrue(app.staticTexts["Sundae"].waitForExistence(timeout: 20))
        snap(app, "02-feed", settle: 5)

        // This week only, then earlier weeks once asked for, at the bottom.
        let earlier = app.buttons["show-earlier-weeks"].firstMatch
        for _ in 0..<12 where !earlier.exists { app.swipeUp() }
        XCTAssertTrue(earlier.waitForExistence(timeout: 5), "the feed ends with a way to earlier weeks")
        snap(app, "02-feed-end-of-week", settle: 1.5)
        // Pulled up past the end and let go: the earlier weeks load, as a pull down refreshes.
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        low.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        if earlier.waitForExistence(timeout: 2) { earlier.tap() }
        app.swipeUp()
        snap(app, "02-feed-earlier-weeks", settle: 3)
        tab(app, "Feed")
        tab(app, "Feed")

        // Open the first friend's profile from a feed header.
        let author = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'author-'")).firstMatch
        if author.waitForExistence(timeout: 8) {
            author.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            snap(app, "03-profile-friend", settle: 5)
            back(app)
        }

        // Dump detail with comments. Back is there whichever edge the system put it on: the
        // page's own header on a phone, the side strip on an iPhone Duo.
        let comments = app.buttons["Comments"].firstMatch
        if comments.waitForExistence(timeout: 5) {
            comments.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            snap(app, "04-dump-detail", settle: 4)
            XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 3), "a way back on every device")
            back(app)
        }

        tab(app, "Notifications")
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 10))
        snap(app, "07-notifications", settle: 4)
        // Riley asked to follow. Confirming lets Riley follow you, and follows nobody back:
        // the row says so and offers Follow back as its own button.
        let confirm = app.buttons["Confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "follow requests are under the heart")
        confirm.tap()
        let followsYou = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Follows you now'")).firstMatch
        XCTAssertTrue(followsYou.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Follow back"].firstMatch.exists, "following back is a choice")
        snap(app, "07-notifications-confirmed", settle: 1.5)

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
        } else {
            snap(app, "02-sunday-prompt-dark-missing", settle: 0)
        }
        XCTAssertTrue(app.staticTexts["Sundae"].waitForExistence(timeout: 20))
        snap(app, "02-feed-dark", settle: 5)
    }
}

/// Every screen again with the phone turned sideways, for the iPhone Duo run.
final class LandscapeScreenshotTests: ScreenshotTests {
    override var landscape: Bool { true }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
}

import XCTest

/// Walks every screen against the mock backend and saves a screenshot of each.
/// Screenshots are attached to the result bundle and, when `SCREENSHOT_DIR` is set,
/// written straight to that folder as `<device>-<name>.png`. The iPhone Duo's files start
/// with `Duo`, and the landscape run's with `DuoLandscape` (LandscapeScreenshotTests).
///
/// The Duo's pose comes from outside: CI folds the simulator before a run (duoctl), and says
/// which pose it is in with `SUNDAE_POSE` (`open`, `half`, or nothing for closed), so the
/// files from each pose keep apart: `DuoOpen-…`, `DuoHalf-…`.
class ScreenshotTests: XCTestCase {
    /// Turned sideways for every screen. The landscape run overrides it.
    var landscape: Bool { false }

    private var device: String {
        let environment = ProcessInfo.processInfo.environment
        let simulator = environment["SIMULATOR_DEVICE_NAME"] ?? ""
        var base = simulator.contains("Duo") ? "Duo" : UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        if base == "Duo", let pose = environment["SUNDAE_POSE"], !pose.isEmpty {
            base += pose.prefix(1).uppercased() + pose.dropFirst()
        }
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
        // The main screen, with the system's strip and clock, unless the app's window is not on it:
        // the Duo open puts the app on its inner display while the main screen stays the cover,
        // which is off and photographs black. Then the window itself is photographed.
        let window = app.windows.firstMatch
        let mainSize = XCUIScreen.main.screenshot().image.size
        let onMain = abs(window.frame.width - mainSize.width) < 2 && abs(window.frame.height - mainSize.height) < 2
        let screenshot = onMain ? XCUIScreen.main.screenshot() : window.screenshot()
        if name.hasPrefix("00-onboarding-intro-film") {
            // Once per run, for the record: how many displays the device shows, the size of the
            // main one and of the app's window. Displays that are off are never asked for a
            // picture: that can wait forever.
            print("[screens] \(device): \(XCUIScreen.screens.count) main \(mainSize) window \(window.frame) shot \(screenshot.image.size)")
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

    /// Back wherever the system put it: the page's own header on a phone, the side strip on an
    /// iPhone Duo (where the system may name the button by the screen it goes back to).
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["Back"].firstMatch
        if named.waitForExistence(timeout: 3) { return named }
        return app.navigationBars.buttons.firstMatch
    }

    private func back(_ app: XCUIApplication) {
        let button = backButton(app)
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
        let begin = app.buttons["Begin"]
        begin.tap()
        if !app.buttons["Get started"].waitForExistence(timeout: 5) {
            // What the test saw when Begin did not move on, for the log.
            print("[probe] begin frame \(begin.frame) hittable \(begin.isHittable) exists \(begin.exists) state \(app.state.rawValue) buttons \(app.buttons.allElementsBoundByIndex.prefix(8).map { $0.label })")
            begin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
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
        var pickCount = min(4, cells.count)
        for i in 0..<pickCount {
            let cell = cells.element(boundBy: i)
            if cell.waitForExistence(timeout: 3) {
                cell.tap()
            } else {
                // The cells were there a moment ago. What is on screen now, and is the app still up.
                print("[probe] cell \(i) gone: state \(app.state.rawValue) cells \(cells.count) buttons \(app.buttons.allElementsBoundByIndex.prefix(10).map { $0.label }) texts \(app.staticTexts.allElementsBoundByIndex.prefix(6).map { $0.label })")
                snap(app, "99-pick-probe", settle: 0.5)
                pickCount = i
                break
            }
        }
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
        // Back to the top of the feed: the tab, tapped again, scrolls its screen up. Tapped once
        // more in case the first tap only came back from a pushed screen.
        tab(app, "Feed")
        tab(app, "Feed")
        Thread.sleep(forTimeInterval: 1.5)
        // If the tab did not scroll it up, drag the feed back to its title by hand.
        var pulls = 0
        while !app.staticTexts["Sundae"].isHittable && pulls < 6 { app.swipeDown(); pulls += 1 }

        // Open the first friend's profile from a feed header: the first one that is on screen,
        // never one scrolled away, which a tap could land beside.
        let authors = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'author-'"))
        if let author = (0..<min(authors.count, 4)).map({ authors.element(boundBy: $0) }).first(where: { $0.isHittable }) {
            author.tap()
            snap(app, "03-profile-friend", settle: 5)
            XCTAssertTrue(backButton(app).waitForExistence(timeout: 3), "a way back from a profile on every device")
            back(app)
            Thread.sleep(forTimeInterval: 1)
        }

        // Dump detail with comments. Back is there whichever edge the system put it on: the
        // page's own header on a phone, the side strip on an iPhone Duo.
        let comments = app.buttons.matching(identifier: "Comments")
        if let comment = (0..<min(comments.count, 4)).map({ comments.element(boundBy: $0) }).first(where: { $0.isHittable }) {
            comment.tap()
            snap(app, "04-dump-detail", settle: 4)
            let hasBack = backButton(app).waitForExistence(timeout: 3)
            if !hasBack {
                // What the test is looking at, so a miss can be read from the log alone.
                print("[back-missing] buttons: \(app.buttons.allElementsBoundByIndex.prefix(12).map { $0.label }) navbars: \(app.navigationBars.count)")
            }
            XCTAssertTrue(hasBack, "a way back from a post on every device")
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

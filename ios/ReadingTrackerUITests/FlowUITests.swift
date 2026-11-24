import XCTest

/// Drives the main flows and saves screenshots (to $SCREENSHOT_DIR when set, and to the test results).
final class FlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = [], access: String = "unlocked") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-access", access] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")   // names may include a folder
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: url)
        }
    }

    /// Taps a tab. On iOS 26 the tab bar shrinks after scrolling down, so scroll back up first if needed.
    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        if !button.waitForExistence(timeout: 2) || !button.isHittable {
            app.swipeDown()
            app.swipeDown()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "missing tab \(name)")
        button.tap()
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Clears a field (whatever is in it) and types new text.
    private func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        let f = app.textFields[id]
        XCTAssertTrue(f.waitForExistence(timeout: 5), "missing field \(id)")
        // Bring the field well into view first: a tap by position doesn't scroll, and the tab bar floats over the bottom.
        for _ in 0..<4 where !f.isHittable || f.frame.maxY > app.frame.height - 140 {
            app.swipeUp(velocity: .slow)
        }
        // Tap at the right-hand end so the cursor lands after any existing text, then delete it all.
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let existing = (f.value as? String) ?? ""
        if !existing.isEmpty, existing != f.placeholderValue || !existing.isEmpty {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        }
        f.typeText(text)
        XCTAssertEqual(f.value as? String, text, "field \(id) should read \(text)")
    }

    func testAddBookTimeAndLog() {
        let app = launch()
        tab(app, "Books")
        app.buttons["addBook"].tap()
        type(app, "addTitle", "The Test Book")
        type(app, "addAuthor", "A. Writer")
        type(app, "addPages", "300")
        app.buttons["addSave"].tap()
        XCTAssertTrue(element(app, "The Test Book").waitForExistence(timeout: 5))

        tab(app, "Today")
        XCTAssertTrue(app.buttons["timerStart"].waitForExistence(timeout: 5))
        type(app, "timerFrom", "20")
        if app.buttons["keyboardDone"].exists { app.buttons["keyboardDone"].tap() }
        // pick a focus sound (it previews, then plays while the timer runs)
        XCTAssertTrue(app.buttons["sound-rain"].waitForExistence(timeout: 5))
        app.buttons["sound-rain"].tap()
        app.buttons["timerStart"].tap()
        XCTAssertTrue(app.buttons["timerPause"].waitForExistence(timeout: 5))
        sleep(2)
        app.buttons["timerPause"].tap()
        XCTAssertTrue(app.buttons["timerResume"].waitForExistence(timeout: 5))
        app.buttons["timerResume"].tap()
        shot(app, "14-timer-with-rain")
        app.buttons["timerDone"].tap()
        type(app, "timerTo", "45")
        // The keyboard covers the card's Log it button, so use the one above the keyboard.
        if app.buttons["keyboardLogIt"].waitForExistence(timeout: 3) {
            app.buttons["keyboardLogIt"].tap()
        } else {
            app.buttons["keyboardDone"].tap()
            app.buttons["timerLog"].tap()
        }
        if !app.buttons["timerStart"].waitForExistence(timeout: 5) {
            shot(app, "fail-after-log")
            let err = app.staticTexts["timerError"]
            XCTFail("timer should reset after logging. Error shown: \(err.exists ? err.label : "none"). Screen:\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.staticTexts["25"].exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS '25'")).count > 0)

        app.buttons["sound-off"].tap()
        tab(app, "Log")
        XCTAssertTrue(app.staticTexts["+25"].waitForExistence(timeout: 5))
    }

    func testSyncSwitchTurnsOffAndOn() {
        let app = launch(["-uitest-sample"])
        tab(app, "Settings")
        let toggle = app.switches["syncToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Settings should have a Sync with iCloud switch")
        XCTAssertEqual(toggle.value as? String, "1", "sync starts on")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()   // the switch itself, at the right-hand end
        XCTAssertEqual(app.switches["syncToggle"].value as? String, "0", "the switch should turn off")
        shot(app, "06b-settings-sync-off")
        let again = app.switches["syncToggle"]
        again.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()   // the switch itself, at the right-hand end
        XCTAssertEqual(app.switches["syncToggle"].value as? String, "1", "and back on")
    }

    func testNotesRatingAndTheme() {
        let app = launch(["-uitest-sample"])
        tab(app, "Books")
        element(app, "Pride and Prejudice").tap()
        XCTAssertTrue(app.buttons["addThought"].waitForExistence(timeout: 5))
        app.buttons["addThought"].tap()
        let text = app.textFields["noteText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Mr Darcy improves on a second reading.")
        app.buttons["noteSave"].tap()
        XCTAssertTrue(app.staticTexts["Mr Darcy improves on a second reading."].waitForExistence(timeout: 5))
        shot(app, "04-book-detail")

        tab(app, "Settings")
        app.buttons["theme-ocean"].tap()
        shot(app, "06-settings")
        tab(app, "Today")
        shot(app, "07-today-ocean")
    }

    func testScreenshots() {
        let app = launch(["-uitest-sample"])
        shot(app, "01-today")
        tab(app, "Books")
        shot(app, "02-books")
        tab(app, "Stats")
        shot(app, "03-stats")
        app.swipeUp()
        shot(app, "03b-stats-more")
        tab(app, "Log")
        shot(app, "05-log")
    }

    /// The App Store set: six screens in story order, saved to AppStore/ (CI uploads them as "app-store-screenshots").
    func testAppStoreScreenshots() {
        var app = launch(["-uitest-sample"])
        // 1. The timer running, with a Focus sound on
        XCTAssertTrue(app.buttons["sound-rain"].waitForExistence(timeout: 5))
        app.buttons["sound-rain"].tap()
        app.buttons["timerStart"].tap()
        XCTAssertTrue(app.buttons["timerPause"].waitForExistence(timeout: 5))
        sleep(3)
        shot(app, "AppStore/1-timer")
        // 2. The library
        tab(app, "Books")
        shot(app, "AppStore/2-books")
        // 3. A book page with rating, progress and notes
        element(app, "Pride and Prejudice").tap()
        XCTAssertTrue(app.buttons["addThought"].waitForExistence(timeout: 5))
        shot(app, "AppStore/3-book")
        // 4. A quote shared as a picture
        let share = app.buttons["shareCard"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.buttons["cardShare"].waitForExistence(timeout: 5))
        if app.buttons["Story"].exists { app.buttons["Story"].tap() }
        if app.buttons["style-Collage"].exists { app.buttons["style-Collage"].tap() }
        shot(app, "AppStore/4-quote-card")
        // 5. Stats, from a fresh start
        app.terminate()
        app = launch(["-uitest-sample"])
        tab(app, "Stats")
        sleep(1)
        shot(app, "AppStore/5-stats")
        // 6. The monthly recap
        XCTAssertTrue(app.buttons["recapMonth"].waitForExistence(timeout: 5))
        app.buttons["recapMonth"].tap()
        XCTAssertTrue(app.buttons["recapShare"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["recapSlides"].swipeLeft()
        sleep(1)
        shot(app, "AppStore/6-recap")
    }

    func testExpiredTrialIsReadOnly() {
        let app = launch(["-uitest-sample"], access: "expired")
        XCTAssertTrue(app.buttons["trialEnded"].waitForExistence(timeout: 5))
        app.buttons["openLog"].tap()
        XCTAssertTrue(app.buttons["buyUnlock"].waitForExistence(timeout: 5), "logging should open the paywall")
        shot(app, "08-paywall")
    }

    func testLookAroundFirstIsReadOnly() {
        let app = launch(["-uitest-sample"], access: "none")
        XCTAssertTrue(app.buttons["lookAround"].waitForExistence(timeout: 5))
        app.buttons["lookAround"].tap()
        XCTAssertTrue(app.buttons["trialNotStarted"].waitForExistence(timeout: 5), "Today should offer the trial")
        tab(app, "Stats")
        tab(app, "Today")
        app.buttons["openLog"].tap()
        XCTAssertTrue(app.buttons["paywallStartTrial"].waitForExistence(timeout: 5), "logging should offer the trial")
        shot(app, "09-paywall-no-trial")
    }

    func testQuoteCard() {
        let app = launch(["-uitest-sample"])
        tab(app, "Books")
        element(app, "Pride and Prejudice").tap()
        let share = app.buttons["shareCard"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.buttons["cardShare"].waitForExistence(timeout: 5), "the card should render and be shareable")
        shot(app, "10-quote-card")
        app.buttons["Story"].tap()
        shot(app, "11-quote-card-story")
        for style in ["Collage", "Dreamy", "Highlighter", "Editorial", "Bookmark"] {
            let b = app.buttons["style-\(style)"]
            if !b.isHittable { app.scrollViews.containing(.button, identifier: "style-Poster").firstMatch.swipeLeft() }
            XCTAssertTrue(b.waitForExistence(timeout: 3), "missing style \(style)")
            b.tap()
            shot(app, "11-quote-card-\(style)")
        }
        app.buttons["Square"].tap()
        shot(app, "11-quote-card-square")
    }

    func testRecap() {
        let app = launch(["-uitest-sample"])
        tab(app, "Stats")
        XCTAssertTrue(app.buttons["recapMonth"].waitForExistence(timeout: 5))
        app.buttons["recapMonth"].tap()
        XCTAssertTrue(app.buttons["recapShare"].waitForExistence(timeout: 5), "the recap should render and be shareable")
        shot(app, "12-recap-intro")
        let slides = app.descendants(matching: .any)["recapSlides"]
        for i in 1...6 {
            slides.swipeLeft()
            shot(app, "12-recap-\(i)")
        }
        app.buttons["Done"].tap()
        app.buttons["recapYear"].tap()
        XCTAssertTrue(app.buttons["recapShare"].waitForExistence(timeout: 5))
        shot(app, "13-year-in-review")
    }

    func testCoverSearchOpensGoogle() {
        let app = launch(["-uitest-sample"])
        tab(app, "Books")
        element(app, "Pride and Prejudice").tap()
        XCTAssertTrue(app.buttons["addThought"].waitForExistence(timeout: 5), "the book page should open")
        let cover = app.descendants(matching: .any)["coverButton"].firstMatch
        if !cover.waitForExistence(timeout: 5) {
            XCTFail("cover button missing. Screen:\n\(app.debugDescription)")
            return
        }
        cover.tap()
        let google = app.buttons["Search Google Images"]
        XCTAssertTrue(google.waitForExistence(timeout: 5), "the cover menu should offer Google Images")
        google.tap()
        XCTAssertTrue(app.buttons["useGoogleImage"].waitForExistence(timeout: 8), "the Google Images sheet should open")
        shot(app, "15-google-cover-search")
        app.buttons["Cancel"].firstMatch.tap()
    }

    func testWelcomeScreen() {
        let app = launch(access: "none")
        XCTAssertTrue(app.buttons["startTrial"].waitForExistence(timeout: 5))
        shot(app, "00-welcome")
    }
}

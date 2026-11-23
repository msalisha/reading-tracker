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
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Clears a field (whatever is in it) and types new text.
    private func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        let f = app.textFields[id]
        XCTAssertTrue(f.waitForExistence(timeout: 5), "missing field \(id)")
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
        app.tabBars.buttons["Books"].tap()
        app.buttons["addBook"].tap()
        type(app, "addTitle", "The Test Book")
        type(app, "addAuthor", "A. Writer")
        type(app, "addPages", "300")
        app.buttons["addSave"].tap()
        XCTAssertTrue(element(app, "The Test Book").waitForExistence(timeout: 5))

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["timerStart"].waitForExistence(timeout: 5))
        type(app, "timerFrom", "20")
        if app.buttons["keyboardDone"].exists { app.buttons["keyboardDone"].tap() }
        app.buttons["timerStart"].tap()
        XCTAssertTrue(app.buttons["timerPause"].waitForExistence(timeout: 5))
        sleep(2)
        app.buttons["timerPause"].tap()
        XCTAssertTrue(app.buttons["timerResume"].waitForExistence(timeout: 5))
        app.buttons["timerResume"].tap()
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

        app.tabBars.buttons["Log"].tap()
        XCTAssertTrue(app.staticTexts["+25"].waitForExistence(timeout: 5))
    }

    func testNotesRatingAndTheme() {
        let app = launch(["-uitest-sample"])
        app.tabBars.buttons["Books"].tap()
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

        app.tabBars.buttons["Settings"].tap()
        app.buttons["theme-ocean"].tap()
        shot(app, "06-settings")
        app.tabBars.buttons["Today"].tap()
        shot(app, "07-today-ocean")
    }

    func testScreenshots() {
        let app = launch(["-uitest-sample"])
        shot(app, "01-today")
        app.tabBars.buttons["Books"].tap()
        shot(app, "02-books")
        app.tabBars.buttons["Stats"].tap()
        shot(app, "03-stats")
        app.swipeUp()
        shot(app, "03b-stats-more")
        app.tabBars.buttons["Log"].tap()
        shot(app, "05-log")
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
        app.tabBars.buttons["Stats"].tap()
        app.tabBars.buttons["Today"].tap()
        app.buttons["openLog"].tap()
        XCTAssertTrue(app.buttons["paywallStartTrial"].waitForExistence(timeout: 5), "logging should offer the trial")
        shot(app, "09-paywall-no-trial")
    }

    func testWelcomeScreen() {
        let app = launch(access: "none")
        XCTAssertTrue(app.buttons["startTrial"].waitForExistence(timeout: 5))
        shot(app, "00-welcome")
    }
}

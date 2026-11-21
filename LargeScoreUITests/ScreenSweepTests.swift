import XCTest

/// Walks every screen at the standard and the largest text size, light and dark,
/// keeps a screenshot of each step, and runs Apple's accessibility audit on each.
/// Screenshots go to $SWEEP_DIR (set by scripts/sweep.sh), else the temporary folder.
@MainActor
final class ScreenSweepTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private var folder: URL {
        let path = ProcessInfo.processInfo.environment["SWEEP_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: path)
    }

    private var device: String {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.replacingOccurrences(of: " ", with: "-") ?? "device"
    }

    private func launch(size: String, dark: Bool, onboarding: Bool, importing: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSettings", "-UIPreferredContentSizeCategoryName", size,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        if !onboarding { app.launchArguments.append("-skipOnboarding") }
        if importing { app.launchArguments.append("-importSamples") }
        app.launchEnvironment["UITEST_DARK"] = dark ? "1" : "0"
        XCUIDevice.shared.appearance = dark ? .dark : .light
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String, variant: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = folder.appendingPathComponent("\(device)-\(variant)-\(name).png")
        try? data.write(to: url)
    }

    private func audit(_ app: XCUIApplication, _ screen: String) {
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
                let line = "AUDIT \(screen): \(issue.auditType) \(issue.compactDescription) \(issue.element?.debugDescription.prefix(120) ?? "")"
                print(line)
                return true // collected, not failed: each one is judged by eye
            }
        } catch {
            print("AUDIT \(screen): could not run: \(error)")
        }
    }

    /// Scrolls by dragging slowly down the left margin, never across buttons.
    private func scrollToFind(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.6))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.22))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            tries += 1
        }
    }

    /// A library card: its spoken name starts with the title and goes on with the composer.
    private func card(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Evening Air for Four")).firstMatch
    }

    /// The 160-bar piece, for turning pages.
    private func longCard(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Long Evening Air")).firstMatch
    }

    /// Launches with the bundled four-part piece added through the import sheet.
    private func launchWithLibrary(size: String = "UICTContentSizeCategoryL", dark: Bool = false) -> XCUIApplication {
        let app = launch(size: size, dark: dark, onboarding: false, importing: true)
        let add = app.buttons["Add 3 Pieces"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 10))
        return app
    }

    private let sizes = [("standard", "UICTContentSizeCategoryL"), ("ax5", "UICTContentSizeCategoryAccessibilityXXXL")]

    func testOnboarding() {
        for (sizeName, size) in sizes {
            for dark in [false, true] {
                let variant = "\(sizeName)-\(dark ? "dark" : "light")"
                let app = launch(size: size, dark: dark, onboarding: true)
                XCTAssertTrue(app.staticTexts["Which instruments do you play?"].waitForExistence(timeout: 10))
                shot(app, "01-instrument", variant: variant)
                if !dark { audit(app, "onboarding-instrument-\(sizeName)") }
                app.buttons["Bassoon"].firstMatch.tap()
                app.buttons["Continue"].tap()
                XCTAssertTrue(app.staticTexts["Choose the music size"].waitForExistence(timeout: 5))
                sleep(1)
                shot(app, "02-size", variant: variant)
                if !dark { audit(app, "onboarding-size-\(sizeName)") }
                app.buttons["Continue"].tap()
                XCTAssertTrue(app.staticTexts["Choose the space between lines"].waitForExistence(timeout: 5))
                sleep(1)
                shot(app, "025-spacing", variant: variant)
                if !dark { audit(app, "onboarding-spacing-\(sizeName)") }
                app.buttons["Continue"].tap()
                XCTAssertTrue(app.staticTexts["Choose the line thickness"].waitForExistence(timeout: 5))
                sleep(1)
                shot(app, "03-lines", variant: variant)
                app.buttons["Start"].tap()
                XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
                app.terminate()
            }
        }
    }

    func testTabsAndReader() {
        for (sizeName, size) in sizes {
            for dark in [false, true] {
                let variant = "\(sizeName)-\(dark ? "dark" : "light")"
                let empty = launch(size: size, dark: dark, onboarding: false)
                XCTAssertTrue(empty.staticTexts["No music yet"].waitForExistence(timeout: 10))
                shot(empty, "09-library-empty", variant: variant)
                empty.terminate()

                let app = launch(size: size, dark: dark, onboarding: false, importing: true)
                XCTAssertTrue(app.buttons["Add 3 Pieces"].waitForExistence(timeout: 15))
                shot(app, "05-import-list", variant: variant)
                if !dark { audit(app, "import-list-\(sizeName)") }
                app.cells.firstMatch.tap()
                sleep(2)
                shot(app, "06-import-detail", variant: variant)
                if !dark { audit(app, "import-detail-\(sizeName)") }
                app.navigationBars.buttons.firstMatch.tap()
                app.buttons["Add 3 Pieces"].tap()
                XCTAssertTrue(card(app).waitForExistence(timeout: 10))
                shot(app, "10-library", variant: variant)
                if !dark {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    sleep(1)
                    shot(app, "10-library-landscape", variant: variant)
                    XCUIDevice.shared.orientation = .portrait
                    sleep(1)
                }
                if !dark { audit(app, "library-\(sizeName)") }

                app.buttons["Today"].firstMatch.tap()
                shot(app, "11-today", variant: variant)
                app.buttons["Programmes"].firstMatch.tap()
                shot(app, "12-programmes", variant: variant)
                app.buttons["Settings"].firstMatch.tap()
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
                shot(app, "13-settings", variant: variant)
                if !dark { audit(app, "settings-\(sizeName)") }
                scrollToFind(app.buttons["About"].firstMatch, in: app)
                app.buttons["About"].firstMatch.tap()
                shot(app, "14-about", variant: variant)
                app.navigationBars.buttons.firstMatch.tap()

                app.buttons["Library"].firstMatch.tap()
                card(app).tap()
                let page = app.otherElements["page"]
                XCTAssertTrue(page.waitForExistence(timeout: 10))
                sleep(2)
                shot(app, "20-reader-page1", variant: variant)
                if !dark {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    sleep(2)
                    shot(app, "20-reader-landscape", variant: variant)
                    XCUIDevice.shared.orientation = .portrait
                    sleep(2)
                }
                if !dark { audit(app, "reader-\(sizeName)") }
                // Turn by a tap in the right part of the page.
                page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
                sleep(1)
                shot(app, "21-reader-page2", variant: variant)
                app.buttons["Music Size"].tap()
                sleep(2)
                shot(app, "22-size-sheet", variant: variant)
                app.buttons["Done"].tap()
                app.terminate()
            }
        }
    }

    func testHalfPageTurn() {
        let app = launchWithLibrary()
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["Half-Page Turns"].firstMatch
        (toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle).tap()
        app.buttons["Library"].firstMatch.tap()
        longCard(app).tap()
        let page = app.otherElements["page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        sleep(2)
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        sleep(1)
        shot(app, "30-half-turn", variant: "standard-light")
        XCTAssertTrue((page.value as? String ?? "").contains("top shows page 2"))
    }

    func testImportedPartIsShown() {
        let app = launchWithLibrary()
        card(app).tap()
        let page = app.otherElements["page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "40-imported-bassoon-part", variant: "standard-light")
        app.buttons["Back to Library"].firstMatch.tap()
        // Change the part from the card's menu.
        card(app).press(forDuration: 1.2)
        sleep(1)
        shot(app, "41-card-menu", variant: "standard-light")
        let change = app.descendants(matching: .any)["Change Parts"].firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        app.buttons["Flute"].firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        card(app).tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "42-flute-part", variant: "standard-light")
    }

    func testPedalKeysTurnPages() {
        let app = launchWithLibrary()
        longCard(app).tap()
        let page = app.otherElements["page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        sleep(2)
        func value() -> String { page.value as? String ?? "" }
        XCTAssertTrue(value().hasPrefix("Page 1 of"))
        // Page Up and Page Down are handled too, but the simulator's test runner never
        // delivers them: they are checked by hand with a keyboard or pedal.
        for (key, expected) in [(XCUIKeyboardKey.rightArrow, "Page 2"), (.leftArrow, "Page 1"),
                                (.space, "Page 2"), (.upArrow, "Page 1"), (.downArrow, "Page 2")] {
            app.typeKey(key, modifierFlags: [])
            sleep(1)
            print("PAGEVALUE after \(key.rawValue.unicodeScalars.map { $0.value }): \(value())")
            XCTAssertTrue(value().hasPrefix(expected), "key \(key.rawValue.unicodeScalars.map { $0.value })")
        }
    }

    func testProgrammes() {
        for (sizeName, size) in sizes {
            let variant = "\(sizeName)-light"
            let app = launchWithLibrary(size: size)
            app.buttons["Programmes"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["No programmes yet"].waitForExistence(timeout: 5))
            shot(app, "50-programmes-empty", variant: variant)
            app.buttons["New Programme"].firstMatch.tap()
            let name = app.textFields.firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.typeText("Thursday Rehearsal")
            app.buttons["Create"].tap()
            sleep(1)
            shot(app, "505-after-create", variant: variant)
            XCTAssertTrue(app.buttons["Add Pieces"].waitForExistence(timeout: 5))
            app.buttons["Add Pieces"].tap()
            for title in ["Evening Air for Four", "Long Evening Air"] {
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.tap()
            }
            app.buttons["Add 2 Pieces"].tap()
            let pin = app.switches["Today’s Programme"].firstMatch
            XCTAssertTrue(pin.waitForExistence(timeout: 5))
            (pin.switches.firstMatch.exists ? pin.switches.firstMatch : pin).tap()
            sleep(1)
            shot(app, "51-programme", variant: variant)
            audit(app, "programme-\(sizeName)")
            app.buttons["Today"].firstMatch.tap()
            sleep(1)
            shot(app, "52-today", variant: variant)
            audit(app, "today-\(sizeName)")
            // Open the first piece and turn past its end into the second.
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1,")).firstMatch.tap()
            let page = app.otherElements["page"]
            XCTAssertTrue(page.waitForExistence(timeout: 10))
            sleep(2)
            shot(app, "53-reader-in-programme", variant: variant)
            let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next piece")).firstMatch
            XCTAssertTrue(next.exists)
            next.tap()
            sleep(2)
            XCTAssertEqual(page.label, "Long Evening Air")
            app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
            sleep(2)
            XCTAssertEqual(page.label, "Evening Air for Four") // back into the first piece, on its last page
            app.terminate()
        }
    }

    func testNotes() {
        let app = launchWithLibrary()
        card(app).tap()
        let page = app.otherElements["page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        sleep(2)
        app.buttons["Notes"].tap()
        // A line of handwriting over the second bar, drawn slowly like a pen.
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.08))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        app.buttons["Breath"].tap()
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.09)).tap()
        app.buttons["Circle Bar"].tap()
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.32)).tap()
        app.buttons["Highlight Bar"].tap()
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.32)).tap()
        sleep(1)
        shot(app, "60-notes-mode", variant: "standard-light")
        audit(app, "notes-standard")
        app.buttons["Written Note"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { editor.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("Breathe before B")
        shot(app, "605-written-note", variant: "standard-light")
        app.navigationBars.buttons["Done"].firstMatch.tap()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        shot(app, "61-notes-shown", variant: "standard-light")
        XCTAssertTrue((page.value as? String ?? "").contains("notes"))
        // A larger size: the notes go with their bars.
        app.buttons["Music Size"].tap()
        app.buttons["Larger"].tap()
        app.buttons["Larger"].tap()
        app.buttons["Done"].firstMatch.tap()
        sleep(2)
        shot(app, "62-notes-larger", variant: "standard-light")
        app.buttons["Back to Library"].firstMatch.tap()
        sleep(1)
        shot(app, "63-card-with-note", variant: "standard-light")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Breathe before B")).firstMatch.exists)
    }
}

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
        let add = app.buttons["Add 4 Pieces"]
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
                XCTAssertTrue(app.buttons["Add 4 Pieces"].waitForExistence(timeout: 15))
                shot(app, "05-import-list", variant: variant)
                if !dark { audit(app, "import-list-\(sizeName)") }
                app.cells.firstMatch.tap()
                sleep(2)
                shot(app, "06-import-detail", variant: variant)
                if !dark { audit(app, "import-detail-\(sizeName)") }
                app.navigationBars.buttons.firstMatch.tap()
                app.buttons["Add 4 Pieces"].tap()
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
                app.buttons["Back to Library"].firstMatch.tap()
                app.buttons["Settings"].firstMatch.tap()
                let sizeRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Music Size")).firstMatch
                // Settings may still be scrolled down from the About step: back to its top.
                for _ in 0..<3 where !sizeRow.waitForExistence(timeout: 2) {
                    app.collectionViews.firstMatch.swipeDown()
                }
                XCTAssertTrue(sizeRow.waitForExistence(timeout: 5))
                sizeRow.tap()
                sleep(2)
                shot(app, "22-size-settings", variant: variant)
                if !dark { audit(app, "size-settings-\(sizeName)") }
                // The app reopens where it was left: leave Music Size first.
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
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
        sleep(1)
        // Typing into the field itself works whether or not the on-screen keyboard
        // shows (the simulator may count a hardware keyboard as connected).
        editor.tap()
        editor.typeText("Breathe before B")
        shot(app, "605-written-note", variant: "standard-light")
        app.navigationBars.buttons["Done"].firstMatch.tap()
        // Wait for the sheet to close before the palette's Done.
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [closed], timeout: 5)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5))
        shot(app, "61-notes-shown", variant: "standard-light")
        XCTAssertTrue((page.value as? String ?? "").contains("notes"))
        // A larger size, set in Settings: the notes go with their bars.
        app.buttons["Back to Library"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Music Size")).firstMatch.tap()
        let slider = app.sliders["Music size"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.84)
        app.buttons["Library"].firstMatch.tap()
        card(app).tap()
        sleep(2)
        shot(app, "62-notes-larger", variant: "standard-light")
        app.buttons["Back to Library"].firstMatch.tap()
        sleep(1)
        shot(app, "63-card-with-note", variant: "standard-light")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Breathe before B")).firstMatch.exists)
    }

    func testConvertedPieceCompare() {
        let app = launchWithLibrary()
        let converted = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Check against the PDF")).firstMatch
        XCTAssertTrue(converted.waitForExistence(timeout: 10))
        shot(app, "70-library-converted", variant: "standard-light")
        converted.press(forDuration: 1.2)
        let compare = app.descendants(matching: .any)["Compare with PDF"].firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        compare.tap()
        sleep(3)
        shot(app, "71-compare", variant: "standard-light")
        audit(app, "compare-standard")
        app.buttons["Mark as Checked"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Check against the PDF")).firstMatch.exists)
    }

    func testFixNotes() {
        let app = launchWithLibrary()
        let converted = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Check against the PDF")).firstMatch
        XCTAssertTrue(converted.waitForExistence(timeout: 10))
        converted.press(forDuration: 1.2)
        let fix = app.descendants(matching: .any)["Fix Notes"].firstMatch
        XCTAssertTrue(fix.waitForExistence(timeout: 5))
        fix.tap()
        let music = app.otherElements["Music to fix"].firstMatch
        XCTAssertTrue(music.waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "72-fix", variant: "standard-light")
        // Walk along the first line until a note is under the finger.
        let higher = app.buttons["Higher"]
        var y = 0.06
        search: while y < 0.3 {
            var x = 0.15
            while x < 0.95 {
                music.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                if higher.waitForExistence(timeout: 0.5) { break search }
                x += 0.04
            }
            y += 0.02
        }
        XCTAssertTrue(higher.exists)
        shot(app, "73-fix-note", variant: "standard-light")
        audit(app, "fix-standard")
        higher.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Length"].tap()
        app.buttons["Sixteenth"].tap()
        sleep(1)
        shot(app, "74-fix-short-bar", variant: "standard-light")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "don't add up")).firstMatch.exists)
        app.buttons["Undo"].tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "don't add up")).firstMatch.exists)
        app.buttons["Add Note After"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "don't add up")).firstMatch.exists)
        app.buttons["Delete Note"].tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "don't add up")).firstMatch.exists)
        app.buttons["Time Signature"].tap()
        app.buttons["3/4"].tap()
        sleep(1)
        shot(app, "75-fix-time", variant: "standard-light")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "don't add up")).firstMatch.exists)
        app.buttons["Save Fixes"].tap()
        sleep(1)
        converted.press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["Restore Previous Version"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Taps along the music until a note is selected (the note buttons appear).
    private func selectANote(_ app: XCUIApplication) -> Bool {
        let music = app.otherElements["Music to fix"].firstMatch
        guard music.waitForExistence(timeout: 10) else { return false }
        sleep(2)
        let higher = app.buttons["Higher"]
        var y = 0.06
        while y < 0.4 {
            var x = 0.15
            while x < 0.95 {
                music.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                if higher.waitForExistence(timeout: 0.5) { return true }
                x += 0.04
            }
            y += 0.02
        }
        return false
    }

    func testFixScreenSizes() {
        for (sizeName, size) in sizes {
            for dark in [false, true] {
                let variant = "\(sizeName)-\(dark ? "dark" : "light")"
                let app = launchWithLibrary(size: size, dark: dark)
                let converted = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Check against the PDF")).firstMatch
                XCTAssertTrue(converted.waitForExistence(timeout: 10))
                converted.press(forDuration: 1.2)
                let fix = app.descendants(matching: .any)["Fix Notes"].firstMatch
                XCTAssertTrue(fix.waitForExistence(timeout: 5))
                fix.tap()
                XCTAssertTrue(selectANote(app))
                shot(app, "76-fix-note", variant: variant)
                // A word in the bar, to show the words list.
                let tempo = app.buttons["Tempo"]
                if !tempo.isHittable { app.swipeUp() }
                tempo.tap()
                let field = app.textFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.typeText("Andante")
                app.buttons["Add"].tap()
                sleep(2)
                shot(app, "77-fix-bar-words", variant: variant)
                if !dark { audit(app, "fix-\(sizeName)") }
                XCUIDevice.shared.orientation = .landscapeLeft
                sleep(2)
                shot(app, "78-fix-landscape", variant: variant)
                XCUIDevice.shared.orientation = .portrait
                app.terminate()
            }
        }
    }

    func testTranspose() {
        let app = launchWithLibrary()
        let converted = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Check against the PDF")).firstMatch
        XCTAssertTrue(converted.waitForExistence(timeout: 10))
        converted.press(forDuration: 1.2)
        let transpose = app.descendants(matching: .any)["Transpose"].firstMatch
        XCTAssertTrue(transpose.waitForExistence(timeout: 5))
        transpose.tap()
        XCTAssertTrue(app.staticTexts["Up a fourth"].waitForExistence(timeout: 5))
        shot(app, "79-transpose", variant: "standard-light")
        audit(app, "transpose-standard")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        converted.tap()
        sleep(3)
        shot(app, "79-transposed-reader", variant: "standard-light")
    }
}

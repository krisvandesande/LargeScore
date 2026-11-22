import XCTest

/// Writes each screen's accessibility tree in VoiceOver's reading order to
/// $VOICEOVER_DIR (docs/voiceover through scripts/sweep.sh), checks that every
/// control has a spoken name, and runs the contrast audit on its own.
@MainActor
final class AccessibilityTreeTests: XCTestCase {
    private var folder: URL? {
        ProcessInfo.processInfo.environment["VOICEOVER_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private var device: String {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.replacingOccurrences(of: " ", with: "-") ?? "device"
    }

    private var nameless: [String] = []

    private func launch(_ extra: [String] = [], dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSettings", "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + extra
        XCUIDevice.shared.appearance = dark ? .dark : .light
        app.launch()
        return app
    }

    private func libraryApp(dark: Bool = false) -> XCUIApplication {
        let app = launch(["-skipOnboarding", "-importSamples"], dark: dark)
        let add = app.buttons["Add 4 Pieces"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 10))
        return app
    }

    private func card(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Evening Air for Four")).firstMatch
    }

    /// One line per element VoiceOver stops on or reads, in tree order.
    private func record(_ app: XCUIApplication, _ screen: String) {
        guard let snapshot = try? app.snapshot() else { return }
        var lines: [String] = []
        // A menu or switch shows as a named control around an unnamed inner one;
        // VoiceOver stops on the outer, so only the outermost control is checked.
        func walk(_ element: XCUIElementSnapshot, depth: Int, insideNamedControl: Bool = false) {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (element.value as? String) ?? ""
            let interesting: [XCUIElement.ElementType] = [.button, .staticText, .textField, .textView, .switch, .cell, .slider, .searchField, .menuButton, .navigationBar]
            if interesting.contains(element.elementType) || element.identifier == "page" {
                var line = "\(element.elementType.name): \(label)"
                if !value.isEmpty { line += " = \(value)" }
                if !element.identifier.isEmpty && element.identifier != label { line += " [\(element.identifier)]" }
                if !label.isEmpty || !value.isEmpty { lines.append(String(repeating: "  ", count: min(depth, 6)) + line) }
                let control: [XCUIElement.ElementType] = [.button, .switch, .textField, .textView, .slider, .searchField]
                if control.contains(element.elementType), label.isEmpty, element.isEnabled, !insideNamedControl {
                    nameless.append("\(screen): \(element.elementType.name) at \(element.frame)")
                }
                if label.contains(".") && !label.contains(" ") && label.lowercased() == label {
                    nameless.append("\(screen): raw name \"\(label)\"")
                }
            }
            let named = insideNamedControl || ([.button, .switch, .menuButton].contains(element.elementType) && !element.label.isEmpty)
            for child in element.children { walk(child, depth: depth + 1, insideNamedControl: named) }
        }
        walk(snapshot, depth: 0)
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: folder.appendingPathComponent("\(device)-\(screen).txt"), atomically: true, encoding: .utf8)
    }

    func testReadingOrderAndNames() {
        let first = launch()
        XCTAssertTrue(first.staticTexts["Which instruments do you play?"].waitForExistence(timeout: 10))
        record(first, "01-onboarding-instruments")
        first.buttons["Bassoon"].firstMatch.tap()
        first.buttons["Continue"].tap()
        sleep(1)
        record(first, "02-onboarding-size")
        first.terminate()

        let importing = launch(["-skipOnboarding", "-importSamples"])
        XCTAssertTrue(importing.buttons["Add 4 Pieces"].waitForExistence(timeout: 15))
        record(importing, "03-import-list")
        importing.cells.firstMatch.tap()
        sleep(1)
        record(importing, "04-import-detail")
        importing.terminate()

        let app = libraryApp()
        record(app, "05-library")
        app.buttons["Settings"].firstMatch.tap()
        sleep(1)
        record(app, "06-settings")
        app.buttons["Programmes"].firstMatch.tap()
        sleep(1)
        record(app, "07-programmes-empty")
        app.buttons["Library"].firstMatch.tap()
        card(app).tap()
        XCTAssertTrue(app.otherElements["page"].waitForExistence(timeout: 10))
        sleep(2)
        record(app, "08-reader")
        app.buttons["Notes"].tap()
        sleep(1)
        record(app, "09-notes")
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Music Size"].tap()
        sleep(1)
        record(app, "10-size-sheet")

        XCTAssertTrue(nameless.isEmpty, "Controls without a spoken name or with a raw one:\n" + nameless.joined(separator: "\n"))
    }

    /// Contrast is the audit's slowest pass, so it runs on its own, on the large iPad.
    func testContrast() throws {
        guard device.contains("Pro") else { throw XCTSkip("Contrast runs on the iPad Pro only") }
        for dark in [false, true] {
            // Dark from launch: switching while running caught screens mid-change.
            let app = libraryApp(dark: dark)
            sleep(1)
            let screens: [(String, () -> Void)] = [
                ("library", {}),
                ("settings", { app.buttons["Settings"].firstMatch.tap() }),
                ("reader", { app.buttons["Library"].firstMatch.tap(); self.card(app).tap(); sleep(2) }),
                ("notes", { app.buttons["Notes"].tap(); sleep(1) }),
            ]
            for (name, go) in screens {
                go()
                try? app.performAccessibilityAudit(for: .contrast) { issue in
                    print("CONTRAST \(dark ? "dark" : "light") \(name): \(issue.compactDescription) \(issue.element?.label ?? "")")
                    return true
                }
            }
            app.terminate()
        }
    }
}

private extension XCUIElement.ElementType {
    var name: String {
        switch self {
        case .button: "Button"
        case .staticText: "Text"
        case .textField: "TextField"
        case .textView: "TextView"
        case .switch: "Switch"
        case .cell: "Cell"
        case .slider: "Slider"
        case .searchField: "SearchField"
        case .menuButton: "MenuButton"
        case .navigationBar: "NavigationBar"
        case .other: "Other"
        default: "Element \(rawValue)"
        }
    }
}

//
//  UITestSupport.swift
//  ProofOfPathUITests
//

import XCTest

extension XCUIApplication {

    /// Launches with a clean container so each test starts from a known state.
    static func launchFresh(resetData: Bool = true, skipOnboarding: Bool = false) -> XCUIApplication {
        // The app is portrait-only on iPhone; make sure the device agrees before
        // the run so element frames are in the geometry the app was built for.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.terminate()
        if resetData { app.launchArguments += ["-POPResetData"] }
        if skipOnboarding { app.launchArguments += ["-POPSkipOnboarding"] }
        app.launch()
        return app
    }
}

extension XCTestCase {

    @discardableResult
    func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Timed out waiting for \(element.debugDescription)",
            file: file, line: line
        )
        return element
    }

    /// Waits for the element to become hittable, letting any transition finish.
    @discardableResult
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            usleep(150_000)
        }
        return element.exists && element.isHittable
    }

    /// Taps an element once it exists.
    ///
    /// Uses a normalised coordinate rather than `element.tap()`. XCUITest
    /// otherwise runs a "scroll to visible" AX action first, and SwiftUI
    /// intermittently reports frames offset by a full screen width during a
    /// transition, which makes that action fail on a perfectly visible control.
    func tap(_ element: XCUIElement, _ timeout: TimeInterval = 10,
             file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, timeout, file: file, line: line)
        _ = waitUntilHittable(element, timeout: 3)
        usleep(200_000)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Types into a field, clearing whatever is already there.
    ///
    /// SwiftUI reports the placeholder as `value` while a field is empty, so the
    /// placeholder is compared before deciding whether anything needs clearing.
    func type(_ text: String, into field: XCUIElement, timeout: TimeInterval = 10,
              file: StaticString = #filePath, line: UInt = #line) {
        tap(field, timeout, file: file, line: line)

        let app = XCUIApplication()
        var attempts = 0
        while !app.keyboards.firstMatch.waitForExistence(timeout: 3) && attempts < 3 {
            // A tap can be swallowed while a sheet is still presenting.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            attempts += 1
        }
        XCTAssertTrue(app.keyboards.count > 0,
                      "Keyboard never appeared for \(field.debugDescription)",
                      file: file, line: line)

        if let existing = field.value as? String,
           !existing.isEmpty,
           existing != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(text)
    }

    /// Types into a multi-line editor.
    func typeIntoEditor(_ text: String, _ editor: XCUIElement,
                        file: StaticString = #filePath, line: UInt = #line) {
        tap(editor, 10, file: file, line: line)
        let app = XCUIApplication()
        var attempts = 0
        while !app.keyboards.firstMatch.waitForExistence(timeout: 3) && attempts < 3 {
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            attempts += 1
        }
        XCTAssertTrue(app.keyboards.count > 0,
                      "Keyboard never appeared for the editor", file: file, line: line)
        editor.typeText(text)
    }

    /// Scrolls the first scroll view until the element is on screen.
    @discardableResult
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        var swipes = 0
        while swipes < maxSwipes {
            if element.exists && element.isHittable { return true }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// Dismisses the keyboard by tapping a neutral point, then waits for it to go.
    func dismissKeyboardIfPresent(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10)).tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 4)
    }
}

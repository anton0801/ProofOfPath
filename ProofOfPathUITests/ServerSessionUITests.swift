//
//  ServerSessionUITests.swift
//  ProofOfPathUITests
//
//  Online-first behaviour: saves go to the server, and without a connection
//  the app shows the saved copy read-only.
//

import XCTest

final class ServerSessionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSavedDataStaysReadableOfflineButCannotBeChanged() {
        let app = XCUIApplication.launchFresh(skipOnboarding: true)
        waitFor(app.buttons["home.createFirstDecision"], 20)
        screenshot("session-01-home-online")
        tap(app.buttons["home.createFirstDecision"])

        waitFor(app.staticTexts["What Are You Deciding?"])
        type("Choose a phone plan", into: app.textFields["wizard.titleField"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])
        waitFor(app.staticTexts["Desired Outcome"])
        typeIntoEditor("Unlimited data under 30 a month", app.textViews["wizard.outcomeEditor"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])
        waitFor(app.staticTexts["Limits"])
        tap(app.buttons["wizard.continue"])
        waitFor(app.staticTexts["Review Decision Brief"])
        tap(app.buttons["wizard.createWorkspace"])

        // Only reachable once the server stored the decision.
        waitFor(app.staticTexts["Decision Brief"], 20)
        screenshot("session-02-workspace-saved")

        // Relaunch with the server out of reach.
        app.terminate()
        let offline = XCUIApplication()
        offline.launchArguments = ["-POPAPIBaseURL", "http://127.0.0.1:9/api/v1"]
        offline.launch()

        waitFor(offline.staticTexts["Choose a phone plan"], 20)
        waitFor(offline.staticTexts["No connection — viewing saved data"], 30)
        screenshot("session-03-offline-home")
        XCTAssertFalse(offline.buttons["home.createDecision"].isEnabled,
                       "Creating a decision needs a connection")

        // Back online: the banner goes away and editing is possible again.
        offline.terminate()
        let online = XCUIApplication()
        online.launchArguments = ["-POPAPIBaseURL", XCUIApplication.testAPI]
        online.launch()
        waitFor(online.staticTexts["Choose a phone plan"], 20)
        let banner = online.staticTexts["No connection — viewing saved data"]
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10))
        let create = online.buttons["home.createDecision"]
        waitFor(create, 20)
        let deadline = Date().addingTimeInterval(15)
        while !create.isEnabled && Date() < deadline { usleep(200_000) }
        XCTAssertTrue(create.isEnabled)
        screenshot("session-04-back-online")
    }

    func testFirstLaunchWithoutServerExplainsAndRetries() {
        let app = XCUIApplication.launchFresh(api: "http://127.0.0.1:9/api/v1")
        waitFor(app.staticTexts["Can't reach ProofPath"], 30)
        XCTAssertTrue(app.buttons["connection.retry"].exists)
        screenshot("session-05-unavailable")
    }
}

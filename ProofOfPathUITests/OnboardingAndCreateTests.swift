//
//  OnboardingAndCreateTests.swift
//  ProofOfPathUITests
//
//  Drives the app the way a person does: real taps, real typing, real saves.
//  Controls are addressed by accessibility identifier so a label shared between
//  two screens can never resolve to the wrong element.
//

import XCTest

final class OnboardingAndCreateTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Onboarding

    func testOnboardingRunsThroughAllFourScreensAndCanBeSkipped() {
        let app = XCUIApplication.launchFresh()

        waitFor(app.staticTexts["Make Decisions with Evidence"])
        tap(app.buttons["onboarding.continue"])

        waitFor(app.staticTexts["Define What Matters"])
        tap(app.buttons["onboarding.continue"])

        waitFor(app.staticTexts["Separate Facts from Assumptions"])
        tap(app.buttons["onboarding.continue"])

        waitFor(app.staticTexts["Create Your First Decision"])
        XCTAssertTrue(app.buttons["onboarding.create"].exists,
                      "The final onboarding screen must offer the create action")

        tap(app.buttons["onboarding.explore"])
        waitFor(app.staticTexts["Turn a Difficult Choice into a Clear Process"])
    }

    func testSkipJumpsStraightToTheLastScreen() {
        let app = XCUIApplication.launchFresh()
        waitFor(app.staticTexts["Make Decisions with Evidence"])
        tap(app.buttons["onboarding.skip"])
        waitFor(app.staticTexts["Create Your First Decision"])
        XCTAssertFalse(app.buttons["onboarding.skip"].exists,
                       "Skip should disappear on the last screen")
    }

    // MARK: - Empty state

    func testEmptyHomeShowsTheSpecCopy() {
        let app = launchOnHome()
        XCTAssertTrue(app.staticTexts["Define what matters, compare real evidence, and record why you made the final choice."].exists)
        XCTAssertTrue(app.buttons["home.createFirstDecision"].exists)
    }

    // MARK: - Create wizard

    func testWizardBlocksAdvancingWithoutRequiredFields() {
        let app = launchOnHome()
        tap(app.buttons["home.createFirstDecision"])

        waitFor(app.staticTexts["What Are You Deciding?"])
        tap(app.buttons["wizard.continue"])

        XCTAssertTrue(app.staticTexts["A decision title is required."].waitForExistence(timeout: 5),
                      "Expected the title validation message")
        XCTAssertTrue(app.staticTexts["What Are You Deciding?"].exists,
                      "The wizard must stay on step 1 until the title is valid")
    }

    func testWizardBlocksAdvancingWithoutADesiredOutcome() {
        let app = launchOnHome()
        tap(app.buttons["home.createFirstDecision"])

        waitFor(app.staticTexts["What Are You Deciding?"])
        type("Outcome check", into: app.textFields["wizard.titleField"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        waitFor(app.staticTexts["Desired Outcome"])
        tap(app.buttons["wizard.continue"])
        XCTAssertTrue(app.staticTexts["Describe what a good result looks like."].waitForExistence(timeout: 5),
                      "Expected the desired-outcome validation message")
    }

    func testCreateDecisionEndToEndAndItPersists() {
        let app = launchOnHome()
        tap(app.buttons["home.createFirstDecision"])

        // --- Step 1
        waitFor(app.staticTexts["What Are You Deciding?"])
        type("Replace the fridge", into: app.textFields["wizard.titleField"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        // --- Step 2
        waitFor(app.staticTexts["Desired Outcome"])
        typeIntoEditor("Quiet, fits the alcove, lasts eight years", app.textViews["wizard.outcomeEditor"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        // --- Step 3
        waitFor(app.staticTexts["Limits"])
        tap(app.buttons["wizard.continue"])

        // --- Step 4
        waitFor(app.staticTexts["Review Decision Brief"])
        XCTAssertTrue(app.staticTexts["Replace the fridge"].exists,
                      "The review step must show what was typed")
        tap(app.buttons["wizard.createWorkspace"])

        // "Create Workspace" must land in the workspace, not back on the list.
        waitFor(app.staticTexts["Decision Brief"], 15)
        XCTAssertTrue(app.staticTexts["Quiet, fits the alcove, lasts eight years"].exists,
                      "The desired outcome must survive into the brief")

        // Relaunch WITHOUT resetting — the decision must still be there.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-POPAPIBaseURL", XCUIApplication.testAPI]
        relaunched.launch()
        waitFor(relaunched.staticTexts["Replace the fridge"], 15)
    }

    func testSaveAsDraftKeepsTheDecisionOnTheList() {
        let app = launchOnHome()
        tap(app.buttons["home.createFirstDecision"])

        waitFor(app.staticTexts["What Are You Deciding?"])
        type("Draft decision", into: app.textFields["wizard.titleField"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        waitFor(app.staticTexts["Desired Outcome"])
        typeIntoEditor("Not started yet", app.textViews["wizard.outcomeEditor"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        waitFor(app.staticTexts["Limits"])
        tap(app.buttons["wizard.continue"])

        waitFor(app.staticTexts["Review Decision Brief"])
        tap(app.buttons["wizard.saveDraft"])

        waitFor(app.staticTexts["Draft decision"], 15)
    }

    func testBudgetValidationRejectsAnInvertedRange() {
        let app = launchOnHome()
        tap(app.buttons["home.createFirstDecision"])

        waitFor(app.staticTexts["What Are You Deciding?"])
        type("Budget check", into: app.textFields["wizard.titleField"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        waitFor(app.staticTexts["Desired Outcome"])
        typeIntoEditor("Something sensible", app.textViews["wizard.outcomeEditor"])
        dismissKeyboardIfPresent(app)
        tap(app.buttons["wizard.continue"])

        waitFor(app.staticTexts["Limits"])
        type("900", into: app.textFields["wizard.budgetMin"])
        type("100", into: app.textFields["wizard.budgetMax"])
        dismissKeyboardIfPresent(app)

        XCTAssertTrue(
            app.staticTexts["The minimum budget cannot be higher than the maximum."].waitForExistence(timeout: 6),
            "An inverted budget range must be reported"
        )

        tap(app.buttons["wizard.continue"])
        XCTAssertTrue(app.staticTexts["Limits"].exists,
                      "The wizard must not advance while the budget range is invalid")
    }

    func testCancellingTheWizardAsksBeforeDiscarding() {
        let app = launchOnHome()
        tap(app.buttons["home.createFirstDecision"])

        waitFor(app.staticTexts["What Are You Deciding?"])
        type("Half-finished", into: app.textFields["wizard.titleField"])
        dismissKeyboardIfPresent(app)

        tap(app.buttons["wizard.cancel"])
        waitFor(app.alerts["Discard this decision?"])
        tap(app.alerts.buttons["Keep editing"])
        XCTAssertTrue(app.staticTexts["What Are You Deciding?"].waitForExistence(timeout: 5),
                      "Keep editing must return to the wizard")

        tap(app.buttons["wizard.cancel"])
        waitFor(app.alerts["Discard this decision?"])
        tap(app.alerts.buttons["Discard"])
        waitFor(app.staticTexts["Turn a Difficult Choice into a Clear Process"])
    }

    // MARK: - Helper

    /// Starts on Home. Onboarding has its own dedicated tests, so the wizard
    /// tests do not re-walk it as a fragile precondition.
    private func launchOnHome() -> XCUIApplication {
        let app = XCUIApplication.launchFresh(skipOnboarding: true)
        waitFor(app.staticTexts["Turn a Difficult Choice into a Clear Process"])
        waitFor(app.buttons["home.createFirstDecision"])
        return app
    }
}

import XCTest

/// Smoke tests for the Niyora breath home (pre-session) screen.
///
/// These tests rely on the accessibility labels defined in
/// `NiyoraCompanion/BreathHomeView.swift`:
///   - Wordmark group → "Niyora"
///   - Profile button → "My Soul"
///   - Speaker button → "Mute" / "Unmute" (toggles on tap)
///   - Begin button   → "Begin {technique name}"
///   - Rotate button  → "Try a different one" (with hint
///                      "Choose another technique")
///
/// The orb itself is `.accessibilityHidden(true)`, so we look for the
/// visible technique name as the proxy "something is on screen".
final class BreathHomeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Best-effort lookup of the currently displayed technique label.
    ///
    /// The technique name is the largest static text on the home screen
    /// that is not the wordmark "NIYORA", the tagline "Calm in 60 seconds",
    /// the BEGIN button text, or the "Try a different one" rotate text.
    /// We exclude those known strings and return the first remaining
    /// static text that exists.
    private func currentTechniqueLabel(in app: XCUIApplication) -> String? {
        let excluded: Set<String> = [
            "NIYORA",
            "Niyora",
            "Calm in 60 seconds",
            "BEGIN",
            "Try a different one"
        ]
        for i in 0..<app.staticTexts.count {
            let element = app.staticTexts.element(boundBy: i)
            guard element.exists else { continue }
            let label = element.label
            if label.isEmpty { continue }
            if excluded.contains(label) { continue }
            // Subtitle has a middle dot " · "; skip it, we want the name.
            if label.contains("·") { continue }
            return label
        }
        return nil
    }

    // MARK: - Tests

    func test_homeScreen_showsCoreElements() {
        let app = launchApp()

        // Wordmark — combined accessibility element labelled "Niyora".
        let wordmark = app.staticTexts["Niyora"]
        XCTAssertTrue(
            wordmark.waitForExistence(timeout: 5),
            "NIYORA wordmark should be visible on the home screen"
        )

        // Orb is accessibilityHidden, so look for the technique label
        // as a proxy for "the orb area rendered".
        let technique = currentTechniqueLabel(in: app)
        XCTAssertNotNil(
            technique,
            "A technique name label should be visible under the orb"
        )

        // BEGIN button — its accessibility label is "Begin {technique}".
        // Use a predicate match because the technique name is dynamic.
        let beginPredicate = NSPredicate(format: "label BEGINSWITH 'Begin '")
        let beginButton = app.buttons.matching(beginPredicate).firstMatch
        XCTAssertTrue(
            beginButton.exists,
            "BEGIN button should be visible on the home screen"
        )

        // Rotate button — exact label match.
        let rotateButton = app.buttons["Try a different one"]
        XCTAssertTrue(
            rotateButton.exists,
            "'Try a different one' button should be visible"
        )
    }

    func test_tryADifferentOne_rotatesTechnique() {
        let app = launchApp()

        let rotateButton = app.buttons["Try a different one"]
        XCTAssertTrue(
            rotateButton.waitForExistence(timeout: 5),
            "Rotate button should appear"
        )

        let before = currentTechniqueLabel(in: app)
        XCTAssertNotNil(before, "Should have a technique label before rotating")

        rotateButton.tap()

        // The rotate animation is instant (state change), but give the
        // accessibility tree a brief moment to settle.
        let after = currentTechniqueLabel(in: app)
        XCTAssertNotNil(after, "Should still have a technique label after rotating")
        XCTAssertNotEqual(
            before, after,
            "Technique label should change after tapping 'Try a different one'"
        )
    }

    func test_muteButton_togglesAccessibilityLabel() {
        let app = launchApp()

        let muteButton = app.buttons["Mute"]
        XCTAssertTrue(
            muteButton.waitForExistence(timeout: 5),
            "Speaker button should start labelled 'Mute' (audio on)"
        )

        muteButton.tap()

        let unmuteButton = app.buttons["Unmute"]
        XCTAssertTrue(
            unmuteButton.waitForExistence(timeout: 2),
            "After tapping, speaker button should now be labelled 'Unmute'"
        )

        unmuteButton.tap()

        let muteAgain = app.buttons["Mute"]
        XCTAssertTrue(
            muteAgain.waitForExistence(timeout: 2),
            "After tapping again, speaker button should be back to 'Mute'"
        )
    }

    func test_beginButton_isHittable() {
        let app = launchApp()

        let beginPredicate = NSPredicate(format: "label BEGINSWITH 'Begin '")
        let beginButton = app.buttons.matching(beginPredicate).firstMatch
        XCTAssertTrue(
            beginButton.waitForExistence(timeout: 5),
            "BEGIN button should exist on the home screen"
        )
        XCTAssertTrue(
            beginButton.isHittable,
            "BEGIN button should be hittable (visible and enabled)"
        )
        // Intentionally do not tap — that opens the session flow,
        // which has its own dedicated tests.
    }
}

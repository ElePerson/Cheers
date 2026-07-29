import XCTest

final class AuthenticationAccessibilityUITests: XCTestCase {
    func testProductionIdentityAtLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-reset-session",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let serverIdentity = app.descendants(matching: .any)["server-identity-card"]
        XCTAssertTrue(serverIdentity.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign in"].exists)
        XCTAssertTrue(app.buttons["Advanced server settings"].exists)
    }

    func testCustomServerWarningAtLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-reset-session",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let advanced = app.buttons["Advanced server settings"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 10))
        advanced.tap()

        let serverField = app.textFields["server-url-field"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        serverField.tap()
        serverField.typeKey("a", modifierFlags: .command)
        serverField.typeText("http://localhost:30080/api/v1")

        let identity = app.descendants(matching: .any)["server-identity-card"]
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Accounts and data on this server may differ from Cheers Cloud."].exists)
    }
}

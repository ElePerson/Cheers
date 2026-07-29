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
}

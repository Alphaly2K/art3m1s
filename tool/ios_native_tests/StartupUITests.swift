import XCTest

final class StartupUITests: XCTestCase {
  func testStartupAndForeground() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "moe.alphaly.art3m1s")
    app.launch()
    let retry = app.buttons["startup.retry"]
    if retry.waitForExistence(timeout: 3) {
      XCTAssertTrue(app.buttons["startup.share"].exists)
      retry.tap()
    }
    let settings = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "\u{8bbe}\u{7f6e}")).firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 40), app.debugDescription)
    settings.tap()
    let graphics = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "\u{56fe}\u{5f62}\u{540e}\u{7aef}")).firstMatch
    XCTAssertTrue(graphics.waitForExistence(timeout: 5), app.debugDescription)
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(graphics.waitForExistence(timeout: 5))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(graphics.waitForExistence(timeout: 5))
    XCUIDevice.shared.orientation = .portrait
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.terminate()
    app.launch()
    XCTAssertTrue(settings.waitForExistence(timeout: 40), app.debugDescription)
    XCTAssertFalse(app.buttons["startup.retry"].exists)
  }
}

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    setupSnapshot(app)
    app.launchArguments = ["--screenshots"]
    app.launch()
  }

  func testScreenshots() throws {
    // Wait for bootstrap → focused (MockRemindersService resolves instantly)
    let taskCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Install'")).firstMatch
    XCTAssertTrue(taskCard.waitForExistence(timeout: 5))

    snapshot("01-TaskFocus")

    // Tap trash to trigger the undo toast, then capture immediately
    app.buttons["Trash"].tap()
    let undoToast = app.buttons["Undo"]
    XCTAssertTrue(undoToast.waitForExistence(timeout: 3))
    snapshot("02-UndoToast")

    // Open list picker
    app.navigationBars.buttons.firstMatch.tap()
    snapshot("03-ListPicker")

    // Dismiss picker
    app.tap()
  }
}

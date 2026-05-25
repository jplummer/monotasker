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
    // Wait for bootstrap → focused: Trash button appears only in the focused phase
    let trashButton = app.buttons["Trash"]
    XCTAssertTrue(trashButton.waitForExistence(timeout: 5))

    snapshot("01-TaskFocus")

    // Tap trash, wait for undo toast to appear, then let the slide animation finish
    trashButton.tap()
    let undoToast = app.buttons["Task deleted. Undo"]
    XCTAssertTrue(undoToast.waitForExistence(timeout: 3))
    Thread.sleep(forTimeInterval: 0.5)
    snapshot("02-UndoToast")

    // Open list picker
    app.navigationBars.buttons.firstMatch.tap()
    snapshot("03-ListPicker")

    // Dismiss picker
    app.tap()
  }
}

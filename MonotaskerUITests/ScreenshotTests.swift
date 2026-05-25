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

    // Tap trash and wait for the undo toast animation to settle (easeInOut 0.22s)
    trashButton.tap()
    Thread.sleep(forTimeInterval: 1.0)
    snapshot("02-UndoToast")

    // Open list picker
    app.navigationBars.buttons.firstMatch.tap()
    snapshot("03-ListPicker")

    // Dismiss picker
    app.tap()
  }
}

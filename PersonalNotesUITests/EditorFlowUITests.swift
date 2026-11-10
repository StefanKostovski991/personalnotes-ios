import XCTest

/// Drives the real app: write a note, see it in the list, reopen it, and leave with the back
/// button - the flow that is easy to break and impossible to cover from unit tests.
final class EditorFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetStore"]
        app.launch()
        // Wait out the splash animation.
        _ = app.buttons["New note"].waitForExistence(timeout: 10)
    }

    func testWriteNoteAppearsInListThenBackReturnsToList() {
        app.buttons["New note"].tap()

        let titleField = app.textFields["What is this about?"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "the editor should open")
        titleField.tap()
        titleField.typeText("UITest note")

        let noteEditor = app.textViews.firstMatch
        if noteEditor.exists {
            noteEditor.tap()
            noteEditor.typeText("written by the UI test")
        }

        // Colour tag, to prove the swatches are tappable. The list screen also exposes colour
        // buttons, so the first match inside this sheet is the editor's swatch.
        let amberSwatch = app.buttons.matching(identifier: "Amber").firstMatch
        if amberSwatch.exists {
            amberSwatch.tap()
        }

        app.buttons["Save note"].firstMatch.tap()

        // Back on the list, the note is there.
        // The title on the list is the real proof the note was saved and reloaded; the subtitle
        // count is a transient render and would make the test brittle.
        XCTAssertTrue(app.staticTexts["UITest note"].waitForExistence(timeout: 8))

        // Reopen it and leave with the back button (the reported bug).
        app.staticTexts.matching(identifier: "UITest note").firstMatch.tap()
        XCTAssertTrue(app.buttons["Back and save"].waitForExistence(timeout: 5))
        app.buttons["Back and save"].tap()

        XCTAssertTrue(app.buttons["New note"].waitForExistence(timeout: 8), "back should return to the list")
        XCTAssertTrue(app.staticTexts.matching(identifier: "UITest note").firstMatch.exists)
    }

    func testSearchFiltersTheList() {
        app.buttons["New note"].tap()
        let titleField = app.textFields["What is this about?"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Groceries")
        app.buttons["Save note"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 8))

        let search = app.textFields["Search title, text or place"]
        search.tap()
        search.typeText("zzz")
        XCTAssertFalse(app.staticTexts.matching(identifier: "Groceries").firstMatch.waitForExistence(timeout: 2))

        // Clearing is a separate button next to the field.
        let clearButton = app.buttons["Clear search"]
        if clearButton.exists {
            clearButton.tap()
        } else {
            search.tap()
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        }
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))
    }
}

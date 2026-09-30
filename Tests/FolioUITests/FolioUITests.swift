import XCTest

/// Drives the real app against a throwaway data folder and fixed prices
/// (see Sources/Folio/Testing/TestSupport.swift), so these never touch real data or the network.
///
/// Fixture prices: BTC $100,000 · ETH $4,000 · 1 USD = 0.9 EUR · Milady floor $4,000.
final class FolioUITests: XCTestCase {
    private var dataDirectory = ""
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = "/tmp/FolioUITests/\(UUID().uuidString)"
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(atPath: dataDirectory)
    }

    // MARK: - Tests

    func testEmptyStateOffersEveryAssetType() {
        XCTAssertTrue(app.buttons["Add Crypto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add Cash"].exists)
        XCTAssertTrue(app.buttons["Add NFT"].exists)
    }

    func testAddEditAndDeleteCash() {
        app.buttons["Add Cash"].firstMatch.click()
        type("1234.5", into: "amount")
        type("Savings", into: "label")
        confirm()

        show(section: "3")
        assertSectionTotal("$1,234.50")
        XCTAssertTrue(table("cash-table").staticTexts["USD · Savings"].waitForExistence(timeout: 5))

        // Double-click opens the holding; Edit Holding changes it. Clicks target a cell's blank
        // area (left of the right-aligned balance), so the whole row must be clickable.
        balanceCell().doubleClick()
        XCTAssertTrue(app.staticTexts["holding-balance"].waitForExistence(timeout: 5))
        app.buttons["Edit Holding"].click()
        replace(with: "2000", in: "amount")
        confirm()
        assertValue("$2,000.00", of: "holding-balance")
        show(section: "3")
        assertSectionTotal("$2,000.00")

        // ⌘⌫ (Edit ▸ Delete Holding) removes the selected row.
        balanceCell().click()
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No Cash"].waitForExistence(timeout: 5))
    }

    func testForeignCashIsConvertedToDisplayCurrency() {
        app.typeKey("n", modifierFlags: [.command, .shift])
        let picker = app.popUpButtons["currency"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS '(EUR)'")).firstMatch.click()
        type("90", into: "amount")
        confirm()

        show(section: "3")
        assertSectionTotal("$100.00")  // €90 at 0.9 EUR per USD
    }

    func testAddCryptoFromSearch() {
        app.buttons["Add Crypto"].firstMatch.click()
        type("bit", into: "coin-search")
        let result = app.buttons["coin-result-bitcoin"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        type("0.5", into: "amount")
        type("Ledger", into: "label")
        confirm()

        show(section: "2")
        assertSectionTotal("$50,000.00")
        XCTAssertTrue(table("crypto-table").staticTexts["Bitcoin"].exists)
        XCTAssertTrue(table("crypto-table").staticTexts["BTC · Ledger"].exists)

        // The overview picks it up too.
        show(section: "1")
        XCTAssertTrue(app.staticTexts["$50,000.00"].firstMatch.waitForExistence(timeout: 5))
    }

    func testAddAndRemoveNFTs() {
        app.buttons["Add NFT"].firstMatch.click()
        type("7, 42", into: "tokens")
        XCTAssertEqual(app.buttons["confirm"].label, "Add 2")
        confirm()

        show(section: "4")
        let seven = app.staticTexts["token-milady-maker-7"]
        XCTAssertTrue(seven.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["token-milady-maker-42"].exists)
        assertSectionTotal("$8,000.00")  // 2 × $4,000 floor

        seven.rightClick()
        app.menuItems["Remove"].click()
        XCTAssertTrue(waitForDisappearance(of: seven))
        assertSectionTotal("$4,000.00")
    }

    func testAddingAnOwnedTokenIsBlocked() {
        app.buttons["Add NFT"].firstMatch.click()
        type("7", into: "tokens")
        confirm()

        app.typeKey("n", modifierFlags: [.command, .option])
        type("7", into: "tokens")
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"),
                                                 object: app.buttons["confirm"])
        XCTAssertEqual(XCTWaiter().wait(for: [disabled], timeout: 5), .completed, "Add should be disabled for an owned token")
    }

    func testHoldingsSurviveRelaunch() {
        app.buttons["Add Cash"].firstMatch.click()
        type("500", into: "amount")
        confirm()

        app.terminate()
        app = launchApp()
        show(section: "3")
        assertSectionTotal("$500.00")
    }

    func testSellingReducesBalanceAndDeletingTheSaleRestoresIt() {
        addCrypto("eth", id: "ethereum", amount: "6.2")
        show(section: "2")
        openFirstHolding(in: "crypto-table")
        assertValue("6.2 ETH", of: "holding-balance")

        app.buttons["Add Transaction"].click()
        app.radioButtons["Sell"].click()
        type("2", into: "quantity")
        assertValue("Balance after: 4.2 ETH", of: "balance-after")
        confirm()

        assertValue("4.2 ETH", of: "holding-balance")
        assertValue("$16,800.00", of: "holding-value")  // 4.2 × $4,000
        XCTAssertTrue(table("transactions-table").staticTexts["Sell"].exists)

        // The list reflects the new balance too.
        show(section: "2")
        assertSectionTotal("$16,800.00")
        XCTAssertTrue(table("crypto-table").staticTexts["4.2 ETH"].exists)

        // Deleting the sale puts the 2 ETH back.
        openFirstHolding(in: "crypto-table")
        table("transactions-table").outlineRows.firstMatch.cells.element(boundBy: 1).rightClick()
        contextMenuItem("Delete").click()
        assertValue("6.2 ETH", of: "holding-balance")
    }

    func testCannotSellMoreThanYouHold() {
        addCrypto("eth", id: "ethereum", amount: "6.2")
        show(section: "2")
        openFirstHolding(in: "crypto-table")

        app.buttons["Add Transaction"].click()
        app.radioButtons["Sell"].click()
        type("10", into: "quantity")
        XCTAssertTrue(app.staticTexts["You only have 6.2 ETH."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm"].isEnabled)
    }

    func testCashWithdrawal() {
        app.typeKey("n", modifierFlags: [.command, .shift])
        type("1000", into: "amount")
        confirm()
        show(section: "3")
        openFirstHolding(in: "cash-table")

        app.typeKey("t", modifierFlags: .command)  // File ▸ Add Transaction…
        app.radioButtons["Withdrawal"].click()
        type("250", into: "quantity")
        confirm()

        assertValue("$750.00", of: "holding-balance")
        show(section: "3")
        assertSectionTotal("$750.00")
    }

    func testPortfolioMovesToICloudDriveAndReachesAnotherMac() {
        // Before iCloud Drive: the portfolio lives on this Mac.
        app.typeKey("n", modifierFlags: [.command, .shift])
        type("500", into: "amount")
        confirm()
        app.terminate()

        // iCloud Drive available: the portfolio moves there and still shows up.
        let iCloud = "/tmp/FolioUITests/\(UUID().uuidString)-icloud"
        app = launchApp(iCloudRoot: iCloud)
        show(section: "3")
        assertSectionTotal("$500.00")
        app.terminate()

        // Another Mac with nothing stored locally, same iCloud Drive: same portfolio.
        dataDirectory = "/tmp/FolioUITests/\(UUID().uuidString)"
        app = launchApp(iCloudRoot: iCloud)
        show(section: "3")
        assertSectionTotal("$500.00")
    }

    // MARK: - Helpers

    private func launchApp(iCloudRoot: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["FOLIO_DATA_DIR": dataDirectory, "FOLIO_STUB_MARKET": "1"]
        if let iCloudRoot { app.launchEnvironment["FOLIO_ICLOUD_ROOT"] = iCloudRoot }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ApplePersistenceIgnoreState", "YES",
                               // Inline predictions race with synthesized typing and eat keystrokes.
                               "-NSAutomaticInlinePredictionEnabled", "NO", "-NSAutomaticTextCompletionEnabled", "NO"]
        app.launch()
        return app
    }

    private func show(section key: String) {
        app.typeKey(key, modifierFlags: .command)
    }

    private func addCrypto(_ query: String, id: String, amount: String) {
        app.typeKey("n", modifierFlags: .command)
        type(query, into: "coin-search")
        let result = app.buttons["coin-result-\(id)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        type(amount, into: "amount")
        confirm()
    }

    /// A context-menu item, as opposed to the Edit menu's standard item of the same name.
    private func contextMenuItem(_ title: String) -> XCUIElement {
        app.menuItems.matching(NSPredicate(format: "title == %@ AND identifier == 'menuAction:'", title)).firstMatch
    }

    /// Double-clicking a holding opens its detail page with the transaction list.
    private func openFirstHolding(in tableID: String) {
        table(tableID).outlineRows.firstMatch.cells.element(boundBy: 1).doubleClick()
        XCTAssertTrue(app.staticTexts["holding-balance"].waitForExistence(timeout: 5), "detail page didn't open")
    }

    private func assertValue(_ expected: String, of id: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts[id]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(id) not found", file: file, line: line)
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [matches], timeout: 5), .completed,
                       "\(id) was \(element.value ?? "nil"), expected \(expected)", file: file, line: line)
    }

    /// Rows report themselves as disabled to accessibility, so click their cells instead.
    private func balanceCell() -> XCUIElement {
        table("cash-table").outlineRows.firstMatch.cells.element(boundBy: 1)
    }

    /// SwiftUI exposes a macOS `Table` to accessibility as an outline.
    private func table(_ id: String) -> XCUIElement {
        let table = app.outlines[id]
        XCTAssertTrue(table.waitForExistence(timeout: 5), "\(id) not shown")
        return table
    }

    /// Presses the sheet's Add/Save once it's enabled, then waits for the sheet to close.
    private func confirm(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["confirm"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed, "confirm never enabled", file: file, line: line)
        button.click()
        XCTAssertTrue(waitForDisappearance(of: app.sheets.firstMatch), "sheet didn't close", file: file, line: line)
    }

    private func type(_ text: String, into id: String, clearing: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field \(id) not found", file: file, line: line)
        field.click()
        if clearing { field.typeKey("a", modifierFlags: .command) }
        field.typeText(text)
        // Synthesized typing is much faster than a person and can occasionally drop a key.
        // Retype once if that happened, then insist the field holds exactly what we typed.
        if field.value as? String != text {
            field.typeKey("a", modifierFlags: .command)
            field.typeText(text)
        }
        XCTAssertEqual(field.value as? String, text, "field \(id)", file: file, line: line)
    }

    private func replace(with text: String, in id: String, file: StaticString = #filePath, line: UInt = #line) {
        type(text, into: id, clearing: true, file: file, line: line)
    }

    private func assertSectionTotal(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let total = app.staticTexts["section-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "no section total", file: file, line: line)
        // On macOS a text element's content is its value, not its label.
        let matches = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: matches, object: total)], timeout: 5)
        XCTAssertEqual(result, .completed, "section total was \(total.value ?? "nil"), expected \(expected)", file: file, line: line)
    }

    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 10) == .completed
    }
}

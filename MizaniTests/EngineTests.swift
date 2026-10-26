import XCTest
@testable import Mizani

@MainActor
final class EngineTests: XCTestCase {
    func testBundledEngineAndNativeDecoding() throws {
        let engine = try WalletEngine()
        let blank = try engine.execute(action: "snapshot", state: nil)
        XCTAssertEqual(blank.state.version, 1)
        XCTAssertTrue(blank.snapshot.accounts.isEmpty)
        let text = "Dear Customer, You have sent OMR 80.000 to TEST PERSON from your a/c 0000XXXXXXXX0017 on 25/10/2026 12:00:05 using Mobile Payment services. Txn Id TEST000001. Avl Bal OMR 49.699."
        let first = try engine.execute(action: "import", state: blank.state, payload: ["text": text])
        XCTAssertEqual(first.result.added, 1)
        XCTAssertEqual(first.snapshot.accounts.first?.balance, 49_699)
        let duplicate = try engine.execute(action: "import", state: first.state, payload: ["text": text])
        XCTAssertEqual(duplicate.result.duplicates, 1)
        XCTAssertEqual(duplicate.state.transactions.count, 1)
    }
    func testInvalidAllocationIsAnError() throws {
        let engine = try WalletEngine()
        let start = try engine.execute(action: "anchor", state: nil, payload: ["account": "TEST", "amount": "1.000"])
        XCTAssertThrowsError(try engine.execute(action: "envelope", state: start.state, payload: ["account": "TEST", "name": "ادخار", "kind": "saving", "amount": "2"]))
    }
    func testNativeOptionalRoundTrip() throws {
        let engine = try WalletEngine()
        let start = try engine.execute(action: "anchor", state: nil, payload: ["account": "TEST", "amount": "100"])
        let expense = try engine.execute(action: "manual", state: start.state, payload: ["account": "TEST", "kind": "expense", "amount": "10", "date": Dates.iso(Date.now.addingTimeInterval(2))])
        let reopened = try engine.execute(action: "snapshot", state: expense.state)
        XCTAssertEqual(reopened.snapshot.accounts.first?.balance, 90_000)
    }
}

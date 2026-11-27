import XCTest
@testable import MarqueeKit

final class MarqueeEdgeFadeTests: XCTestCase {
    func testClearanceMovesTheRestingHeadWithoutWideningTheFade() {
        let edges = MarqueeEdgeFade(length: 10, clearance: 6).resolved(in: 100)
        XCTAssertEqual(edges.length, 10)
        XCTAssertEqual(edges.headInset, 16)
        XCTAssertEqual(edges.fraction, 0.1, accuracy: 0.0001)
    }

    func testSmallViewportsAndInvalidInputsLeaveTheHeadReadable() {
        let large = MarqueeEdgeFade(length: 90, clearance: .greatestFiniteMagnitude)
        XCTAssertEqual(large.resolved(in: 50).headInset, 15)
        XCTAssertEqual(large.resolved(in: 18).headInset, 0)
        XCTAssertEqual(large.resolved(in: .nan).fraction, 0)
        XCTAssertEqual(MarqueeEdgeFade(length: .infinity, clearance: 8).resolved(in: 80).headInset, 0)
        XCTAssertEqual(MarqueeEdgeFade(length: 5, clearance: -3).resolved(in: 80).headInset, 5)
        XCTAssertEqual(MarqueeEdgeFade(length: 0, clearance: 12).resolved(in: 80).headInset, 0)
    }
}

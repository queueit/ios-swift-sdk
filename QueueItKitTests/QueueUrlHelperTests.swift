import XCTest
@testable import QueueItKit

final class QueueUrlHelperTests: XCTestCase {

    func testGetParameter_foundAndDecoded() {
        let query = "name=John+Doe&age=30"
        let value = QueueUrlHelper.getParameter(queryString: query, key: "name")
        XCTAssertEqual(value, "John Doe")
    }

    func testGetParameter_notFound() {
        let query = "name=John"
        let value = QueueUrlHelper.getParameter(queryString: query, key: "age")
        XCTAssertNil(value)
    }

    func testGetParameter_emptyQuery() {
        let value = QueueUrlHelper.getParameter(queryString: "", key: "name")
        XCTAssertNil(value)
    }

    func testIsUrlUpdateNeeded_noQueryItems() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(queueUrlStr: "https://example.com", userId: "123")
        XCTAssertTrue(result)
    }

    func testIsUrlUpdateNeeded_userIdMissing() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(queueUrlStr: "https://example.com?name=John", userId: "123")
        XCTAssertTrue(result)
    }

    func testIsUrlUpdateNeeded_userIdMatches() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(queueUrlStr: "https://example.com?userId=123", userId: "123")
        XCTAssertFalse(result)
    }

    func testIsUrlUpdateNeeded_userIdDifferent() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(queueUrlStr: "https://example.com?userId=456", userId: "123")
        XCTAssertTrue(result)
    }

    func testUpdateUrl_addUserId() {
        let updated = QueueUrlHelper.updateUrl(queueUrlStr: "https://example.com?name=John", userId: "123")
        XCTAssertTrue(updated.contains("userId=123"))
        XCTAssertTrue(updated.contains("name=John"))
    }

    func testUpdateUrl_replaceUserId() {
        let updated = QueueUrlHelper.updateUrl(queueUrlStr: "https://example.com?userId=456", userId: "123")
        XCTAssertTrue(updated.contains("userId=123"))
        XCTAssertFalse(updated.contains("userId=456"))
    }

    func testUpdateUrl_emptyUrl() {
        let updated = QueueUrlHelper.updateUrl(queueUrlStr: "", userId: "123")
        XCTAssertEqual(updated, "")
    }
}

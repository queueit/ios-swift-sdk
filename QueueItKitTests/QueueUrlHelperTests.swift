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

    func testIsUrlUpdateNeeded_inviteCodeMissing() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(
            queueUrlStr: "https://example.com?userId=123",
            userId: "123",
            inviteCode: "ABC123"
        )
        XCTAssertTrue(result)
    }

    func testIsUrlUpdateNeeded_inviteCodeAlreadyPresent() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(
            queueUrlStr: "https://example.com?userId=123&code=ABC123",
            userId: "123",
            inviteCode: "ABC123"
        )
        XCTAssertFalse(result)
    }

    func testIsUrlUpdateNeeded_inviteCodeEmpty() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(
            queueUrlStr: "https://example.com?userId=123",
            userId: "123",
            inviteCode: ""
        )
        XCTAssertFalse(result)
    }

    func testUpdateUrl_addInviteCode() {
        let updated = QueueUrlHelper.updateUrl(
            queueUrlStr: "https://example.com?name=John",
            userId: "123",
            inviteCode: "ABC123"
        )
        XCTAssertTrue(updated.contains("userId=123"))
        XCTAssertTrue(updated.contains("code=ABC123"))
        XCTAssertTrue(updated.contains("name=John"))
    }

    func testUpdateUrl_doesNotDuplicateInviteCode() {
        let updated = QueueUrlHelper.updateUrl(
            queueUrlStr: "https://example.com?code=EXISTING",
            userId: "123",
            inviteCode: "ABC123"
        )
        XCTAssertTrue(updated.contains("code=EXISTING"))
        XCTAssertFalse(updated.contains("code=ABC123"))
    }

    func testUpdateUrl_nilInviteCodeDoesNotAddCodeParam() {
        let updated = QueueUrlHelper.updateUrl(
            queueUrlStr: "https://example.com?name=John",
            userId: "123",
            inviteCode: nil
        )
        XCTAssertFalse(updated.contains("code="))
    }

    func testUpdateUrl_inviteCodeRoundTripsThroughURLComponents() {
        let original = "A B&D=E"
        let updated = QueueUrlHelper.updateUrl(
            queueUrlStr: "https://example.com",
            userId: "123",
            inviteCode: original
        )
        // raw value must not appear unencoded (would break URL parsing)
        XCTAssertFalse(updated.contains("code=\(original)"))

        let parsed = URLComponents(string: updated)?.queryItems?.first(where: { $0.name == "code" })?.value
        XCTAssertEqual(parsed, original)
    }

    func testIsUrlUpdateNeeded_existingCodeDiffersFromPassed() {
        // If a code is already on the URL, passing a different one must not trigger a rewrite.
        let result = QueueUrlHelper.isUrlUpdateNeeded(
            queueUrlStr: "https://example.com?userId=123&code=EXISTING",
            userId: "123",
            inviteCode: "DIFFERENT"
        )
        XCTAssertFalse(result)
    }

    func testIsUrlUpdateNeeded_nilInviteCodeWithExistingCodeParam() {
        let result = QueueUrlHelper.isUrlUpdateNeeded(
            queueUrlStr: "https://example.com?userId=123&code=EXISTING",
            userId: "123",
            inviteCode: nil
        )
        XCTAssertFalse(result)
    }

    func testUpdateUrl_existingCodeWithDifferentCasing_isNotDuplicated() {
        // Lookup is case-insensitive: a URL carrying `Code=…` should not get a second `code=…` appended.
        let updated = QueueUrlHelper.updateUrl(
            queueUrlStr: "https://example.com?Code=EXISTING",
            userId: "123",
            inviteCode: "NEW"
        )
        XCTAssertTrue(updated.contains("Code=EXISTING"))
        XCTAssertFalse(updated.contains("code=NEW"))
    }

    func testUpdateUrl_preservesFragment() {
        let updated = QueueUrlHelper.updateUrl(
            queueUrlStr: "https://example.com?userId=456#section",
            userId: "123",
            inviteCode: "ABC"
        )
        XCTAssertTrue(updated.hasSuffix("#section"))
        XCTAssertTrue(updated.contains("userId=123"))
        XCTAssertTrue(updated.contains("code=ABC"))
    }
}

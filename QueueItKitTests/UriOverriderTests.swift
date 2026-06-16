import XCTest
@testable import QueueItKit

class UriOverriderTests: XCTestCase {

    var testObj: UriOverrider!

    let TEST_QUEUE_URL_HTTP = "https://customer.queue-it.net/app/enqueue"
    let TEST_QUEUE_URL_DEEPLINK = "qapp://enqueue"
    let TEST_TARGET_URL_HTTP = "https://google.com"
    let TEST_TARGET_URL_DEEPLINK = "myapp://page1"

    override func setUp() {
        super.setUp()
        testObj = UriOverrider()
    }

    override func tearDown() {
        testObj = nil
        super.tearDown()
    }

    func testGivenUserNavigatesToCloseLink_thenShouldReturnCloseAction() {
        testObj.setQueueUrl("https://vavatest.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP)

        let result = testObj.handleNavigationRequest("queueit://close")

        XCTAssertEqual(result.action, .close)
    }

    func testGivenUserNavigatesToSessionRestartLink_thenShouldReturnRestartAction() {
        testObj.setQueueUrl("https://vavatest.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP)

        let result = testObj.handleNavigationRequest("queueit://restartSession")

        XCTAssertEqual(result.action, .restartSession)
    }

    func testGivenUserIsNavigatingToBlockedPage_thenShouldReturnBlockAction() {
        testObj.setQueueUrl("https://vavatest.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP)
        let destinationUrl = "https://queue-it.com/what-is-this.html?customerId=vavatest&eventId=testendedroom&queueId=00000000-0000-0000-0000-000000000000&language=en-US"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .block)
    }

    func testGivenNavigatingToDifferentUrl_thenShouldReturnOpenExternal() {
        testObj.setQueueUrl("https://vavatest.queue-it.net/app/enqueue")
        testObj.setTargetUrl("https://google.com/q=iamthetarget")
        
        let destinationUrl = "https://some-other-domain.com"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .openExternal)
    }

    func testGivenUserIsRedirectedToTarget_thenShouldReturnPassed() {
        testObj.setQueueUrl("https://useraccount.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP) // "https://google.com"
        let destinationUrl = "https://google.com?queueittoken=a"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .passed)
    }

    func testGivenNavigatingToExternalPage_thenShouldReturnOpenExternal() {
        testObj.setQueueUrl("https://useraccount.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP)
        let destinationUrl = "https://bing.com"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .openExternal)
    }

    func testGivenTargetIsDeepLinkAndNavigatingToIt_thenShouldReturnOpenExternal() {
        testObj.setQueueUrl(TEST_QUEUE_URL_DEEPLINK) // "qapp://enqueue"
        testObj.setTargetUrl(TEST_TARGET_URL_DEEPLINK) // "myapp://page1"
        let destinationUrl = "myapp://page1" // No token, still opens external (as per test intent)

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .openExternal)
    }

    func testGivenTargetIsHttpAndNavigatingToItWithToken_thenShouldReturnPassed() {
        testObj.setQueueUrl(TEST_QUEUE_URL_DEEPLINK) // "qapp://enqueue"
        testObj.setTargetUrl("https://mypage.com")
        let destinationUrl = "https://mypage.com?queueittoken=1"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .passed)
    }

    func testGivenTargetIsDeepLinkAndNavigatingToItWithoutToken_thenShouldReturnOpenExternal() {
        testObj.setQueueUrl("https://useraccount.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_DEEPLINK) // "myapp://page1"
        let destinationUrl = "myapp://page1"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .openExternal)
    }

    func testGivenNavigatingToExternalDeepUrl_thenShouldReturnOpenExternal() {
        testObj.setQueueUrl("https://useraccount.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP)
        testObj.setUserId("myuser1")
        let destinationUrl = "myapp://go?tab=activity1" // This is an external deep link

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .openExternal)
    }

    func testGivenUserIsNavigatingToQueueUrlPath_ThenShouldReturnLoadInWebview() {
        testObj.setQueueUrl("https://useraccount.queue-it.net/app/enqueue")
        testObj.setTargetUrl(TEST_TARGET_URL_HTTP)
        testObj.setUserId("myuser1")
        let destinationUrl = "https://useraccount.queue-it.net/app/leaveLine"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .loadInWebview)
        
        XCTAssertNotNil(result.modifiedUrl)
        XCTAssertTrue(result.modifiedUrl!.contains("userId=myuser1"))
    }

    func testGivenUserNavigatesToExitLine_thenShouldReturnLoadInWebview() {
        testObj.setQueueUrl(TEST_QUEUE_URL_HTTP) // "https://customer.queue-it.net/app/enqueue"
        testObj.setTargetUrl("http://localhost:3000")
        testObj.setUserId("myuser1")
        let destinationUrl = "http://customer.queue-it.net/exitline.aspx?c=customer&e=otherroom2&q=qid&cid=en-US&l=myLayout&sdkv=iOS-Swift-1.1.0"

        let result = testObj.handleNavigationRequest(destinationUrl)

        XCTAssertEqual(result.action, .loadInWebview)
        XCTAssertNotEqual(result.action, .passed)
        
        XCTAssertNotNil(result.modifiedUrl)
        XCTAssertTrue(result.modifiedUrl!.contains("userId=myuser1"))
    }

    func testGivenNavigatingToQueueItPage_thenUrlShouldBeRewrittenWithUserId() {
        testObj.setQueueUrl(TEST_QUEUE_URL_HTTP) // "https://customer.queue-it.net/app/enqueue"
        testObj.setTargetUrl("http://localhost:3000")
        testObj.setUserId("myuser1")
        let destinationUrl = "http://customer.queue-it.net/exitline.aspx?c=customer&e=otherroom2&q=qid&cid=en-US&l=myLayout&sdkv=iOS-Swift-1.1.0"
        let expectedRewrittenUrlContains = "http://customer.queue-it.net/exitline.aspx?userId=myuser1&c=customer&e=otherroom2&q=qid&cid=en-US&l=myLayout&sdkv=iOS-Swift-1.1.0" // Order of query items might vary

        let result = testObj.handleNavigationRequest(destinationUrl)
        XCTAssertEqual(result.action, .loadInWebview)
        
        XCTAssertNotNil(result.modifiedUrl)
        XCTAssertTrue(result.modifiedUrl!.contains("userId=myuser1"))
    }
    
    // MARK: - Behind Proxy Tests
    
    func testIsBehindProxy_WithWaitingRoomDomain_ShouldReturnTrue() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "queue.mydomain.com")
        
        XCTAssertTrue(testObjWithProxy.isBehindProxy())
    }
    
    func testIsBehindProxy_WithEmptyWaitingRoomDomain_ShouldReturnFalse() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "")
        
        XCTAssertFalse(testObjWithProxy.isBehindProxy())
    }
    
    
    func testIsBehindProxy_WithQueuePathPrefix_ShouldReturnFalse() {
        let testObjWithProxy = UriOverrider(queuePathPrefix: "queue")
        
        XCTAssertFalse(testObjWithProxy.isBehindProxy())
    }
    
    func testIsBehindProxy_WithBothParameters_ShouldReturnTrue() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "mydomain.com", queuePathPrefix: "queue")
        
        XCTAssertTrue(testObjWithProxy.isBehindProxy())
    }
    
    func testIsBehindProxy_WithoutParameters_ShouldReturnFalse() {
        let testObjWithoutProxy = UriOverrider()
        
        XCTAssertFalse(testObjWithoutProxy.isBehindProxy())
    }
    
    func testBehindProxy_WithDomainOnly_ShouldHandleCorrectly() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "queue.mydomain.com")
        testObjWithProxy.setQueueUrl("https://queue.mydomain.com/app/enqueue")
        testObjWithProxy.setTargetUrl("https://mydomain.com/success")
        testObjWithProxy.setUserId("testuser123")
        
        let destinationUrl = "https://queue.mydomain.com/app/status"
        let result = testObjWithProxy.handleNavigationRequest(destinationUrl)
        
        XCTAssertEqual(result.action, .loadInWebview)
        XCTAssertNotNil(result.modifiedUrl)
        XCTAssertTrue(result.modifiedUrl!.contains("userId=testuser123"))
    }
    
    func testBehindProxy_WithDomainAndPrefix_MatchingPath_ShouldHandleCorrectly() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "mydomain.com", queuePathPrefix: "queue")
        testObjWithProxy.setQueueUrl("https://mydomain.com/queue/app/enqueue")
        testObjWithProxy.setTargetUrl("https://mydomain.com/success")
        testObjWithProxy.setUserId("testuser123")
        
        let destinationUrl = "https://mydomain.com/queue/app/status"
        let result = testObjWithProxy.handleNavigationRequest(destinationUrl)
        
        XCTAssertEqual(result.action, .loadInWebview)
        XCTAssertNotNil(result.modifiedUrl)
        XCTAssertTrue(result.modifiedUrl!.contains("userId=testuser123"))
    }
    
    func testBehindProxy_WithDomainAndPrefix_NonMatchingPath_ShouldNotBeTreatedAsQueueUrl() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "mydomain.com", queuePathPrefix: "queue")
        testObjWithProxy.setQueueUrl("https://mydomain.com/queue/app/enqueue")
        testObjWithProxy.setTargetUrl("https://mydomain.com/success")
        testObjWithProxy.setUserId("testuser123")
        
        let destinationUrl = "https://mydomain.com/other/page"
        let result = testObjWithProxy.handleNavigationRequest(destinationUrl)
        
        XCTAssertEqual(result.action, .openExternal)
    }
    
    func testBehindProxy_WithUserIdNeeded_ShouldRewriteUrl() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "queue.mydomain.com")
        testObjWithProxy.setQueueUrl("https://queue.mydomain.com/app/enqueue")
        testObjWithProxy.setTargetUrl("https://mydomain.com/success")
        testObjWithProxy.setUserId("testuser123")
        
        let destinationUrl = "https://queue.mydomain.com/app/status?event=test"
        let result = testObjWithProxy.handleNavigationRequest(destinationUrl)
        
        XCTAssertEqual(result.action, .loadInWebview)
        XCTAssertNotNil(result.modifiedUrl)
        XCTAssertTrue(result.modifiedUrl!.contains("userId=testuser123"))
    }
    
    func testBehindProxy_CaseInsensitiveDomain() {
        let testObjWithProxy = UriOverrider(waitingRoomDomain: "Queue.MyDomain.COM")
        testObjWithProxy.setQueueUrl("https://queue.mydomain.com/app/enqueue")
        testObjWithProxy.setTargetUrl("https://mydomain.com/success")
        testObjWithProxy.setUserId("testuser123")
        
        let destinationUrl = "https://QUEUE.MYDOMAIN.com/app/status"
        let result = testObjWithProxy.handleNavigationRequest(destinationUrl)
        
        XCTAssertEqual(result.action, .loadInWebview)
    }
}


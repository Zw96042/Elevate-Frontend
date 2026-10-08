import Foundation
import Testing
@testable import ElevateCore

@Suite struct NetworkRetryTests {
    /// Failures before connecting retry twice for any request; a lost
    /// connection only for repeatable ones; timeouts, being offline and
    /// cancellation never.
    @Test func onlyTransientConnectionFailuresRetryTwice() {
        #expect(SkywardHTTP.retryDelay(for: .networkConnectionLost, attempt: 0, repeatable: true) == 350)
        #expect(SkywardHTTP.retryDelay(for: .networkConnectionLost, attempt: 1, repeatable: true) == 1_200)
        #expect(SkywardHTTP.retryDelay(for: .networkConnectionLost, attempt: 2, repeatable: true) == nil)
        #expect(SkywardHTTP.retryDelay(for: .networkConnectionLost, attempt: 0, repeatable: false) == nil)
        #expect(SkywardHTTP.retryDelay(for: .cannotConnectToHost, attempt: 0, repeatable: false) != nil)
        #expect(SkywardHTTP.retryDelay(for: .dnsLookupFailed, attempt: 0, repeatable: true) != nil)
        #expect(SkywardHTTP.retryDelay(for: .resourceUnavailable, attempt: 0, repeatable: true) == nil)
        #expect(SkywardHTTP.retryDelay(for: .timedOut, attempt: 0, repeatable: true) == nil)
        #expect(SkywardHTTP.retryDelay(for: .notConnectedToInternet, attempt: 0, repeatable: true) == nil)
        #expect(SkywardHTTP.retryDelay(for: .cancelled, attempt: 0, repeatable: true) == nil)
        #expect(SkywardHTTP.retryDelay(for: .badServerResponse, attempt: 0, repeatable: true) == nil)
    }

    /// Signing in and queuing a report change Skyward's state; everything
    /// else only reads.
    @Test func signInAndQueuingAReportAreNotRepeated() {
        #expect(!SkywardHTTP.isRepeatable([("login", "x"), ("password", "y")]))
        #expect(!SkywardHTTP.isRepeatable([("action", "addToPrintQueue")]))
        #expect(SkywardHTTP.isRepeatable([("action", "checkPrintQueue")]))
        #expect(SkywardHTTP.isRepeatable([("action", "moreMessages"), ("dwd", "z")]))
    }

    /// A connection Skyward drops reads as Skyward's problem, not the
    /// person's network; being offline says so; anything else keeps iOS's text.
    @Test func connectionFailuresSayWhichSideFailed() {
        #expect(SkywardHTTP.connectionMessage(for: .networkConnectionLost)?.hasPrefix("Skyward isn't responding") == true)
        #expect(SkywardHTTP.connectionMessage(for: .cannotConnectToHost)?.hasPrefix("Skyward isn't responding") == true)
        #expect(SkywardHTTP.connectionMessage(for: .notConnectedToInternet)?.hasPrefix("You're offline") == true)
        #expect(SkywardHTTP.connectionMessage(for: .timedOut)?.hasPrefix("Skyward is taking too long") == true)
        #expect(SkywardHTTP.connectionMessage(for: .unsupportedURL) == nil)
    }
}

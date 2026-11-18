import Network
import Testing
@testable import XdeskTransport

@Suite struct BonjourPolicyDeniedTests {
    @Test func recognisesLocalNetworkDenial() {
        #expect(BonjourBrowser.isPolicyDenied(.dns(-65570)))
        #expect(!BonjourBrowser.isPolicyDenied(.dns(-65537)))
        #expect(!BonjourBrowser.isPolicyDenied(.posix(.ECONNREFUSED)))
    }
}

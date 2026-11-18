import Testing
@testable import XdeskAgent

@Test func moduleNameIsStable() {
    #expect(XdeskAgentModule.name == "XdeskAgent")
}

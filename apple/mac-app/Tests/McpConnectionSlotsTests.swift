import Testing
@testable import Xdesk

@Suite struct McpConnectionSlotsTests {
    @Test func releasingTheSameConnectionTwiceFreesOnlyOneSlot() {
        var slots = McpConnectionSlots(limit: 2)
        let first = slots.acquire()
        let second = slots.acquire()
        #expect(first != nil && second != nil)
        #expect(slots.acquire() == nil)
        if let first {
            slots.release(first) // .failed
            slots.release(first) // rồi .cancelled
        }
        #expect(slots.active == 1)
        #expect(slots.acquire() != nil)
        #expect(slots.acquire() == nil, "giới hạn vẫn giữ sau khi một kết nối báo hai trạng thái kết thúc")
    }

    @Test func zeroLimitRefusesEverything() {
        var slots = McpConnectionSlots(limit: 0)
        #expect(slots.acquire() == nil)
        #expect(slots.active == 0)
    }
}

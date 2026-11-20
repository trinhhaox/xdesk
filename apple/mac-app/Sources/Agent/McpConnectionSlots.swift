/// Đếm kết nối MCP đang mở để chặn quá `limit`.
/// Mỗi kết nối trả slot đúng một lần: NWConnection có thể báo `.failed` rồi `.cancelled`,
/// đếm trùng sẽ làm bộ đếm âm và vô hiệu hoá giới hạn.
struct McpConnectionSlots {
    let limit: Int
    private var open: Set<Int> = []
    private var nextId = 0

    init(limit: Int) { self.limit = limit }

    var active: Int { open.count }

    /// Cấp slot cho kết nối mới; nil = đã đầy.
    mutating func acquire() -> Int? {
        guard open.count < limit else { return nil }
        nextId += 1
        open.insert(nextId)
        return nextId
    }

    /// Trả slot; gọi lại với cùng id thì không làm gì.
    mutating func release(_ id: Int) {
        open.remove(id)
    }
}

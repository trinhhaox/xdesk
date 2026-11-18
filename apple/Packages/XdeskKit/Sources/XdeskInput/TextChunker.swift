/// Chia chuỗi theo ranh giới Character (không cắt ký tự ghép/cặp surrogate) sao cho mỗi đoạn có tổng `measure` ≤ `limit`.
/// Một Character lớn hơn `limit` đứng riêng một đoạn (người dùng quyết định bỏ hay cắt).
public enum TextChunker {
    public static func split(_ text: String, limit: Int, measure: (Character) -> Int) -> [String] {
        var chunks: [String] = []
        var current = "", size = 0
        for character in text {
            let cost = measure(character)
            if size + cost > limit, !current.isEmpty {
                chunks.append(current)
                current = ""; size = 0
            }
            current.append(character)
            size += cost
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    public static func splitUtf8(_ text: String, maxBytes: Int) -> [String] {
        split(text, limit: maxBytes) { $0.utf8.count }
    }
}

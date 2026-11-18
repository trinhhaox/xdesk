/// So hai trạng thái văn bản của ô gõ để biết cần xoá lùi bao nhiêu ký tự rồi gõ thêm gì
/// (bộ gõ Telex có thể thay "a" bằng "â" thay vì chỉ nối thêm).
public enum TextEditDiff {
    public struct Edit: Sendable, Equatable {
        public var deleteCount: Int
        public var insert: String
        public var isEmpty: Bool { deleteCount == 0 && insert.isEmpty }
    }

    /// So theo ký tự (grapheme), nên "ế" dựng sẵn hay tổ hợp đều coi là một.
    public static func edit(from old: String, to new: String) -> Edit {
        let oldChars = Array(old), newChars = Array(new)
        var common = 0
        while common < oldChars.count, common < newChars.count, oldChars[common] == newChars[common] { common += 1 }
        return Edit(deleteCount: oldChars.count - common, insert: String(newChars[common...]))
    }
}

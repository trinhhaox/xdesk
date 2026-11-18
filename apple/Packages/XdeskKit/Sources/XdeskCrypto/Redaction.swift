/// Mô tả che bí mật cho kiểu mang khoá/token: `print`, `dump`, `"\(x)"`, debugger và log mặc định đều chỉ thấy `Tên(<redacted>)`.
/// (Kiểu nhạy cảm không-copy được thì không đưa vào các API này được, nên không cần lớp này.)
public protocol Redacted: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension Redacted {
    public var description: String { "\(Self.self)(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

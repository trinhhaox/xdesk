import Foundation
import XdeskAgent

extension JsonValue {
    /// Số (int hoặc double) hữu hạn.
    var numberValue: Double? {
        switch self {
        case .int(let v): Double(v)
        case .double(let v): v.isFinite ? v : nil
        default: nil
        }
    }

    func number(_ key: String) -> Double? { self[key]?.numberValue }
}

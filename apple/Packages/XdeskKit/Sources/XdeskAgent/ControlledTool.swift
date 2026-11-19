import Foundation

/// Bọc handler sau cổng quyền: chưa cấp, đang tạm dừng hoặc hết hạn thì trả lỗi ngay, không chạm vào máy.
public struct ControlledTool: ToolHandler {
    private let arbiter: ControlArbiter
    private let inner: any ToolHandler

    public init(arbiter: ControlArbiter, inner: any ToolHandler) { self.arbiter = arbiter; self.inner = inner }

    public func call(arguments: JsonValue) async -> ToolResult {
        switch await arbiter.authorize() {
        case .allowed: return await inner.call(arguments: arguments)
        case .denied(let reason): return .error(reason, audit: "denied")
        }
    }
}

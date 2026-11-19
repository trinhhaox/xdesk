import Foundation

/// 14 tool của Xdesk (tên tự đặt) cùng JSON Schema đầu vào. Handler thật của nhóm điều khiển nằm ở phase 08b.
public enum ToolSchemas {
    private static func object(_ properties: [String: JsonValue] = [:], required: [String] = []) -> JsonValue {
        ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) }), "additionalProperties": false]
    }

    private static func text(_ description: String) -> JsonValue { ["type": "string", "description": .string(description)] }
    private static func number(_ description: String) -> JsonValue { ["type": "number", "description": .string(description)] }
    private static func choice(_ values: [String], _ description: String) -> JsonValue {
        ["type": "string", "enum": .array(values.map { .string($0) }), "description": .string(description)]
    }

    private static let pointerProps: [String: JsonValue] = [
        "action": choice(["move", "click", "double", "right", "drag"], "Thao tác chuột"),
        "x": number("Toạ độ ngang trên màn hình agent (pixel)"),
        "y": number("Toạ độ dọc trên màn hình agent (pixel)"),
        "ref": text("Mã phần tử từ xdesk_ui_tree, dùng thay cho x,y"),
        "toX": number("Điểm đến ngang khi action là drag"),
        "toY": number("Điểm đến dọc khi action là drag"),
    ]
    private static let scrollProps: [String: JsonValue] = ["dx": number("Cuộn ngang"), "dy": number("Cuộn dọc (dương là xuống)")]
    private static let typeProps: [String: JsonValue] = ["text": text("Chuỗi cần gõ")]
    private static let keysProps: [String: JsonValue] = [
        "keys": ["type": "array", "items": ["type": "string"], "description": "Tổ hợp phím, ví dụ [\"cmd\",\"s\"]"],
    ]

    private static let stepSchema: JsonValue = [
        "type": "object",
        "properties": ["tool": choice(["xdesk_pointer", "xdesk_scroll", "xdesk_type_text", "xdesk_press_keys"], "Tool của bước"), "arguments": object()],
        "required": ["tool", "arguments"],
    ]

    private static func tool(
        _ name: String, _ title: String, _ description: String, _ schema: JsonValue = object(),
        readOnly: Bool = false, destructive: Bool = false, idempotent: Bool = false
    ) -> ToolDefinition {
        ToolDefinition(
            name: name, title: title, description: description, inputSchema: schema,
            readOnly: readOnly, destructive: readOnly ? false : destructive, idempotent: readOnly || idempotent)
    }

    public static let all: [ToolDefinition] = [
        tool("xdesk_status", "Trạng thái Xdesk", "Xem trạng thái chia sẻ màn hình, số viewer, mã hoá, màn hình agent và ai đang giữ quyền điều khiển.", readOnly: true),
        tool("xdesk_request_control", "Xin quyền điều khiển", "Xin quyền điều khiển màn hình agent; người dùng sẽ duyệt trên Mac và điện thoại đã ghép.",
             object(["reason": text("Lý do, hiển thị trong hộp thoại duyệt")], required: ["reason"])),
        tool("xdesk_end_control", "Nhả quyền điều khiển", "Nhả quyền điều khiển đang giữ.", idempotent: true),
        tool("xdesk_screenshot", "Chụp màn hình agent", "Chụp màn hình agent (cạnh dài tối đa 1568 px) kèm hệ toạ độ.", readOnly: true),
        tool("xdesk_ui_tree", "Cây phần tử giao diện", "Liệt kê phần tử giao diện (role, nhãn, khung) của app trên màn hình agent, mỗi phần tử có ref để click.", readOnly: true),
        tool("xdesk_pointer", "Điều khiển chuột", "Di chuyển, click hoặc kéo chuột trên màn hình agent theo toạ độ hoặc ref.",
             object(pointerProps, required: ["action"]), destructive: true),
        tool("xdesk_scroll", "Cuộn", "Cuộn nội dung trên màn hình agent.", object(scrollProps), destructive: true),
        tool("xdesk_type_text", "Gõ chuỗi", "Gõ một chuỗi vào phần tử đang focus trên màn hình agent (không gõ vào ô mật khẩu).",
             object(typeProps, required: ["text"]), destructive: true),
        tool("xdesk_press_keys", "Nhấn tổ hợp phím", "Nhấn một tổ hợp phím trên màn hình agent.", object(keysProps, required: ["keys"]), destructive: true),
        tool("xdesk_run_steps", "Chạy chuỗi bước", "Chạy tối đa 20 bước pointer/scroll/type/keys, dừng ở lỗi đầu tiên.",
             object(["steps": ["type": "array", "maxItems": 20, "items": stepSchema, "description": "Danh sách bước"]], required: ["steps"]), destructive: true),
        tool("xdesk_launch", "Mở app hoặc URL", "Mở app (bundle id) hoặc URL lên màn hình agent, theo luật app.",
             object(["target": text("Bundle id hoặc URL")], required: ["target"])),
        tool("xdesk_set_workspace_size", "Đổi độ phân giải màn hình agent", "Đổi độ phân giải màn hình agent.",
             object(["width": number("Chiều rộng (pixel)"), "height": number("Chiều cao (pixel)")], required: ["width", "height"]), idempotent: true),
        tool("xdesk_clipboard_read", "Đọc clipboard", "Đọc văn bản trong clipboard; bỏ qua mục ẩn (mật khẩu).", readOnly: true),
        tool("xdesk_clipboard_write", "Ghi clipboard", "Ghi văn bản vào clipboard.", object(["text": text("Văn bản cần ghi")], required: ["text"]), destructive: true),
    ]
}

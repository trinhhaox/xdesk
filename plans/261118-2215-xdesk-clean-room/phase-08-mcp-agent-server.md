# Phase 08 — Máy chủ MCP cho agent AI (Claude Code, Cursor, Codex…)

## Context
- Phụ thuộc: 05 (EventInjector, CoordinateMapper), 06 (thông báo duyệt tới thiết bị đã ghép). Song song được với 07.
- Chuẩn: MCP revision 2025-11-25, transport Streamable HTTP (1 endpoint `/mcp`, POST JSON-RPC; GET SSE tuỳ chọn); header `MCP-Protocol-Version`, `Mcp-Session-Id`.
- Tên tool do mình tự đặt (clean-room), không dùng bộ tên của app tham khảo.

## Overview
- Ưu tiên: P1 · pending · 5d
- Agent làm việc trên **màn hình ảo riêng "Bàn làm việc agent"**, người vẫn dùng màn hình chính. Mọi quyền điều khiển phải được người duyệt, có banner tạm dừng/dừng, có luật theo app.

## Key insights
- KISS transport: server chỉ trả `application/json` cho POST (spec cho phép không mở SSE); GET `/mcp` → 405. Đánh giá `modelcontextprotocol/swift-sdk` — nếu có server Streamable HTTP ổn định thì dùng, nếu không tự cài HTTP/1.1 tối thiểu trên `NWListener` (parse request line + header + Content-Length, ≤ 1 MiB) — quyết định ghi ở bước 1.
- Chống DNS rebinding: bind `127.0.0.1` (không `0.0.0.0`); `Host` phải là `127.0.0.1:<port>` hoặc `localhost:<port>`; có `Origin` mà không thuộc allowlist rỗng → 403. Bearer token 32 B ngẫu nhiên trong Keychain, so sánh constant-time; sai 5 lần/phút → khoá 60 s.
- Ảnh chụp: SCK `SCScreenshotManager` chỉ màn hình agent, PNG/JPEG scale ≤ 1568 px cạnh dài để tiết kiệm token, trả kèm hệ toạ độ.
- Phần tử UI: `AXUIElement` duyệt cây của app đang ở màn hình agent → danh sách `{ref, role, label, frame}` (ref là id phiên, sống đến lần `ui_tree` sau) giúp agent click theo ref thay vì đoán pixel.
- Bảo vệ mật khẩu: không gõ khi phần tử focus là `AXSecureTextField` hoặc `IsSecureEventInputEnabled()`; `clipboard_read` bỏ item có type `org.nspasteboard.ConcealedType` / `TransientType` (quy ước nspasteboard.org, 1Password/Bitwarden dùng).
- Tự nhả quyền khi agent im lặng 120 s (cấu hình), khi người chạm chuột/bàn phím thật vào màn hình agent (phát hiện qua CGEventTap nguồn HID thật) → tạm dừng ngay.

## Requirements — bộ tool (đề xuất tên riêng)
| Tool | Mô tả |
|---|---|
| `xdesk_status` | trạng thái phiên, kích thước màn hình agent, ai đang giữ quyền |
| `xdesk_request_control` / `xdesk_end_control` | xin/nhả quyền; xin → hộp thoại duyệt trên Mac + thông báo tới điện thoại đã ghép |
| `xdesk_screenshot` | ảnh màn hình agent |
| `xdesk_ui_tree` | danh sách phần tử AX có ref |
| `xdesk_pointer` | `{action: move/click/double/right/drag, x,y | ref}` |
| `xdesk_scroll`, `xdesk_type_text`, `xdesk_press_keys` | cuộn, gõ chuỗi, tổ hợp phím |
| `xdesk_run_steps` | chuỗi ≤ 20 bước trên, dừng ở lỗi đầu |
| `xdesk_launch` | mở app/URL lên màn hình agent (kiểm luật app) |
| `xdesk_set_workspace_size` | đổi độ phân giải màn hình agent |
| `xdesk_clipboard_read` / `xdesk_clipboard_write` | có bảo vệ mật khẩu |
- Luật theo app (bundle id): `allow` / `ask` / `never`; mặc định `ask`; `never` mặc định cho System Settings mục Privacy, Keychain Access, Terminal (cấu hình được).
- Mọi tool trừ `xdesk_status` yêu cầu quyền đang hiệu lực; thao tác ngoài khung màn hình agent bị từ chối.

## Architecture
```
Agent ──HTTP POST /mcp (Bearer)──► [McpHttpListener 127.0.0.1] → [RequestGuard Host/Origin/token/rate]
 → [JsonRpcRouter] → [ToolRegistry] → [ControlArbiter (người duyệt, idle, pause)] → [AppPolicy]
 → [AgentDisplay(VirtualDisplayProvider)] [AxTreeReader] [EventInjector] [ScreenshotService] [ClipboardGuard]
 → [AuditLog] (JSONL, xoay vòng 7 ngày, không lưu ảnh/chuỗi gõ đầy đủ)
UI: [AgentBanner] luôn trên cùng màn hình agent (Tạm dừng / Dừng), phím tắt dừng toàn cục ⌃⌥⌘.
```

## Related code files (tạo)
- `XdeskAgent/` (logic thuần, test được): `JsonRpcMessage.swift`, `JsonRpcRouter.swift`, `McpLifecycle.swift` (initialize/capabilities), `ToolRegistry.swift`, `ToolSchemas.swift`, `ControlArbiter.swift`, `AppPolicy.swift`, `RequestGuard.swift`, `AuditLog.swift`.
- `mac-app/Sources/Agent/`: `McpHttpListener.swift`, `HttpRequestParser.swift`, `AgentDisplayManager.swift`, `AxTreeReader.swift`, `ScreenshotService.swift`, `ClipboardGuard.swift`, `AgentBanner.swift`, `ApprovalPrompt.swift`, `AgentSettingsView.swift`, `tool handlers/*.swift` (mỗi tool 1 file).
- `docs/mcp-setup.md`: lệnh cấu hình `claude mcp add --transport http xdesk http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`, Cursor, Codex.

## Implementation steps
1. Spike 0.5d: swift-sdk vs tự cài HTTP; chốt.
2. RequestGuard + test (Host sai, Origin lạ, token sai, quá giới hạn).
3. JSON-RPC + lifecycle `initialize` (trả `protocolVersion`, `capabilities.tools`) + `tools/list` + `tools/call`.
4. AgentDisplayManager (màn hình ảo thứ 2, tên "Xdesk Agent").
5. ControlArbiter + ApprovalPrompt (Mac) + thông báo duyệt tới viewer qua control `agent.approve` (iOS/Android hiện nút Cho phép/Từ chối).
6. Tool handlers; AppPolicy; ClipboardGuard; AxTreeReader.
7. AgentBanner + hotkey + idle release + phát hiện người can thiệp.
8. AuditLog + màn Cài đặt (sao chép token, đổi token, luật app).

## Todo
- [ ] Spike SDK
- [ ] RequestGuard
- [ ] JSON-RPC + lifecycle
- [ ] Agent display
- [ ] Arbiter + duyệt trên Mac/điện thoại
- [ ] 12 tool handler
- [ ] Banner/hotkey/idle
- [ ] Audit + settings + docs/mcp-setup.md

## Success criteria
- MCP Inspector kết nối, `tools/list` đủ tool, schema hợp lệ.
- Claude Code: "mở TextEdit trên màn hình agent và gõ Xin chào" → hỏi duyệt trên Mac + iPhone, sau khi cho phép làm xong, ảnh chụp xác nhận.
- `curl -H "Host: evil.com"` → 403; không token → 401; `Origin: http://evil.com` → 403; bind kiểm `lsof -iTCP -sTCP:LISTEN | grep Xdesk` chỉ 127.0.0.1.
- Focus ô mật khẩu Safari → `xdesk_type_text` trả lỗi rõ ràng; clipboard chứa mật khẩu 1Password → `xdesk_clipboard_read` trả rỗng + lý do.
- Nhấn hotkey dừng → tool kế tiếp trả "control paused" ≤ 100 ms.

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Token lộ qua file cấu hình agent | TB×Cao | token chỉ cấp quyền xin điều khiển, vẫn cần người duyệt; đổi token 1 chạm |
| Trang web độc hại gọi localhost (DNS rebinding/CSRF) | TB×Cao | Host/Origin check, bearer bắt buộc, không CORS |
| Agent thao tác nhầm app nhạy cảm | TB×Cao | luật `never`, chỉ màn hình agent, banner + hotkey, audit |
| Cây AX chậm/rỗng (Electron, canvas) | Cao×TB | giới hạn độ sâu/thời gian 500 ms, fallback pixel theo ảnh |
| Spec MCP đổi (revision mới) | TB×Thấp | thương lượng `protocolVersion`, hỗ trợ 2025-06-18 + 2025-11-25 |

## Security
- Không bao giờ bind ngoài loopback; không mở cổng mạng cho MCP ở Tailscale/LAN.
- Audit không ghi nội dung gõ (chỉ độ dài), không ghi ảnh.
- Mặc định MCP TẮT; người dùng bật trong Cài đặt.

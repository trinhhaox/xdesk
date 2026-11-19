# Kết nối agent AI với Xdesk qua MCP

Xdesk có sẵn một máy chủ MCP cục bộ để agent AI (Claude Code, Cursor, Codex…) đọc trạng thái và, từ phase 08b, điều khiển màn hình riêng "Bàn làm việc agent". Mặc định **TẮT**.

> Phase 08a (bản này) chỉ có `xdesk_status` chạy thật. 13 tool còn lại có đủ schema nhưng trả lỗi "Chưa hỗ trợ ở bản này (phase 08b)".

## Bật máy chủ

1. Biểu tượng Xdesk trên thanh menu, bật **Cho phép agent AI (MCP)**.
2. Menu hiện `Agent AI: 127.0.0.1:47810`. Cổng mặc định là **47810** (host chia sẻ màn hình dùng 47800).
3. Đổi cổng: `defaults write vn.xox.xdesk mcp.port -int 47811`, rồi tắt/bật lại công tắc. Giá trị ngoài 1024-65535 bị bỏ qua.
4. Công tắc được nhớ giữa các lần mở app.

Menu có thêm:

- **Sao chép lệnh cấu hình**: chép sẵn lệnh `claude mcp add ...` kèm token vào clipboard (đánh dấu ẩn với trình quản lý clipboard).
- **Đổi token**: tạo token mới ngay, mọi agent đang dùng token cũ nhận 401 và phải cấu hình lại.

## Claude Code

Bấm **Sao chép lệnh cấu hình** rồi dán vào Terminal. Lệnh có dạng:

```sh
claude mcp add --transport http xdesk http://127.0.0.1:47810/mcp --header "Authorization: Bearer <token>"
```

Kiểm tra: `claude mcp list` phải thấy `xdesk` kết nối được; trong Claude Code hỏi "gọi xdesk_status".

## Cursor

Sửa `~/.cursor/mcp.json` (hoặc `.cursor/mcp.json` của dự án). Lấy `<token>` từ phần sau `Bearer ` của lệnh đã sao chép.

```json
{
  "mcpServers": {
    "xdesk": {
      "url": "http://127.0.0.1:47810/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

## Codex

Trong `~/.codex/config.toml`, để token ở biến môi trường thay vì ghi thẳng vào tệp:

```toml
[mcp_servers.xdesk]
url = "http://127.0.0.1:47810/mcp"
bearer_token_env_var = "XDESK_MCP_TOKEN"
```

```sh
export XDESK_MCP_TOKEN="<token>"
```

Tên khoá có thể khác giữa các phiên bản Codex; xem `codex mcp --help` nếu cấu hình không nhận.

## Mô hình bảo mật

- **Chỉ loopback**: lắng nghe duy nhất `127.0.0.1`. Không mở ở LAN hay Tailscale. Kiểm: `lsof -nP -iTCP -sTCP:LISTEN | grep -i xdesk`.
- **Chống DNS rebinding/CSRF**: `Host` phải là `127.0.0.1:<cổng>` hoặc `localhost:<cổng>`, nếu không trả 403. Có header `Origin` (trình duyệt luôn gửi) thì trả 403, danh sách cho phép rỗng. Không có CORS.
- **Bearer token**: 32 byte ngẫu nhiên, lưu trong Keychain, so sánh hằng thời gian. Thiếu hoặc sai trả 401.
- **Chống dò token**: sai 5 lần trong 60 giây thì khoá 60 giây (429, kèm `Retry-After`), kể cả khi sau đó gửi đúng token.
- **Giới hạn**: thân yêu cầu tối đa 1 MiB (413), tối đa 32 kết nối đồng thời, mỗi kết nối đóng sau 1 yêu cầu hoặc 10 giây.
- **Nhật ký kiểm toán**: `~/Library/Application Support/Xdesk/mcp-audit/mcp-audit-YYYY-MM-DD.jsonl` (quyền 0600, xoá sau 7 ngày). Chỉ ghi method, tên tool, kết quả, thời gian; không ghi tham số, chuỗi gõ hay ảnh. Token không bao giờ vào log.
- **Rủi ro token lộ**: token chỉ cho phép *xin* điều khiển; từ phase 08b mọi thao tác còn cần người dùng duyệt trên Mac và điện thoại. Nghi ngờ lộ thì bấm **Đổi token**.

## Giao thức

- Một endpoint `POST /mcp`, JSON-RPC 2.0 một thông điệp mỗi yêu cầu (batch bị từ chối, -32600), trả `application/json`. `GET /mcp` trả 405; `DELETE /mcp` kết thúc phiên.
- Phiên bản hỗ trợ: `2025-11-25` và `2025-06-18` (thương lượng ở `initialize`). Header `MCP-Protocol-Version` không hỗ trợ trả 400.
- `initialize` trả header `Mcp-Session-Id`. Yêu cầu sau đó thiếu header trả 400, phiên không tồn tại trả 404 (hãy `initialize` lại).
- Method: `initialize`, `notifications/initialized` (202), `ping`, `tools/list`, `tools/call`. Method lạ trả -32601, JSON hỏng trả -32700.
- Lỗi của tool đi qua `isError: true` trong kết quả, không phải lỗi JSON-RPC. Tool không tồn tại là -32602.

## Bộ tool (14)

`xdesk_status` (chạy thật), `xdesk_request_control`, `xdesk_end_control`, `xdesk_screenshot`, `xdesk_ui_tree`, `xdesk_pointer`, `xdesk_scroll`, `xdesk_type_text`, `xdesk_press_keys`, `xdesk_run_steps`, `xdesk_launch`, `xdesk_set_workspace_size`, `xdesk_clipboard_read`, `xdesk_clipboard_write`. Schema và annotation (`readOnlyHint`, `destructiveHint`) lấy từ `tools/list`.

## Kiểm thử nhanh

```sh
TOKEN=...   # phần sau "Bearer "
curl -si -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  http://127.0.0.1:47810/mcp
npx @modelcontextprotocol/inspector --cli http://127.0.0.1:47810/mcp --transport http \
  --header "Authorization: Bearer $TOKEN" --method tools/list
```

Bản Debug có cờ `--enable-mcp [tệp]` bật máy chủ không lưu cài đặt và ghi token vào tệp (0600) cho script kiểm thử.

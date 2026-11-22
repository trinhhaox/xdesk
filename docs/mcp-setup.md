# Kết nối agent AI với Xdesk qua MCP

Xdesk có sẵn một máy chủ MCP cục bộ để agent AI (Claude Code, Cursor, Codex…) đọc trạng thái và điều khiển một màn hình ảo riêng tên **"Xdesk Agent"**, không đụng tới màn hình của bạn. Mặc định **TẮT**. Cả 15 tool đều chạy thật; mọi tool ngoài `xdesk_status`, `xdesk_request_control`, `xdesk_end_control` chỉ hoạt động khi bạn đã cấp quyền.

## Bật máy chủ

1. Mở **Cài đặt** của Xdesk (⌘, hoặc biểu tượng Xdesk trên thanh menu › Cài đặt), tab **Agent AI**, bật **Cho phép agent AI (MCP)**.
2. Tab hiện **Địa chỉ** `127.0.0.1:47810`. Cổng mặc định là **47810** (host chia sẻ màn hình dùng 47800).
3. Đổi cổng: `defaults write vn.xox.xdesk mcp.port -int 47811`, rồi tắt/bật lại công tắc. Giá trị ngoài 1024-65535 bị bỏ qua.
4. Công tắc được nhớ giữa các lần mở app.

Tab **Agent AI** có thêm:

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

## Cấp quyền và dừng khẩn cấp

Agent phải gọi `xdesk_request_control` trước. Xdesk hỏi bạn (hộp thoại "Agent AI xin quyền" trên Mac, và cả điện thoại nếu có, xem mục dưới); **chỉ khi bạn bấm Cho phép** màn hình "Xdesk Agent" mới được tạo (mặc định 1280x800, không HiDPI). Không trả lời trong 60 giây là từ chối.

Trong lúc agent điều khiển, một banner luôn nằm trên cùng màn hình agent (không nhận focus, không lọt vào ảnh chụp hay luồng stream):

- **Tạm dừng / Tiếp tục**: khi tạm dừng, mọi tool điều khiển bị chặn tới khi bạn bấm Tiếp tục.
- **Dừng**: kết thúc quyền ngay; agent phải xin lại.
- Phím tắt toàn cục **⌃⌥⌘.** (Control+Option+Command+dấu chấm) **tạm dừng** agent, không cần quyền riêng. Muốn cho chạy tiếp thì bấm **Tiếp tục** trên banner, muốn kết thúc thì bấm **Dừng**.
- Chạm chuột hoặc bàn phím thật vào màn hình agent cũng tự tạm dừng (cần quyền Giám sát đầu vào, xem dưới; bấm vào chính banner thì không tính).
- Agent im lặng quá **120 giây** (mặc định) thì quyền tự nhả; agent phải xin lại.

## Màn hình "Xdesk Agent"

- Sau `xdesk_end_control` (hoặc khi bạn bấm Dừng), màn hình agent **vẫn được giữ** để bạn xem lại kết quả. Banner ẩn đi.
- Gỡ bằng mục **Gỡ màn hình agent** ở tab Agent AI trong Cài đặt (chỉ hiện khi màn hình đang tồn tại). Tắt công tắc MCP cũng gỡ nó.
- Chỉ dùng được khi hệ thống tạo được màn hình ảo thật. Nếu macOS chỉ cho phản chiếu màn hình chính thì Xdesk từ chối cấp, vì agent không bao giờ được điều khiển màn hình của bạn.
- `xdesk_set_workspace_size` đổi kích thước trong khoảng 640x480 đến 3840x2160 (màn hình được tạo lại, `ref` cũ hết hiệu lực).

## Luật theo ứng dụng

Mỗi lần agent thao tác, Xdesk kiểm ứng dụng đích (cửa sổ dưới con trỏ với chuột/cuộn, cửa sổ đang focus với phím) theo luật theo bundle id:

| Luật | Ý nghĩa |
| --- | --- |
| `allow` (Cho phép) | Cho qua |
| `ask` (Hỏi) | Hỏi bạn một lần cho mỗi app trong một lượt cấp quyền (60 giây; hết giờ là từ chối) |
| `never` (Cấm) | Từ chối luôn |

- App chưa có luật: **hỏi**.
- Mặc định chặn (`never`): Cài đặt hệ thống (`com.apple.systempreferences`, kể cả mở thẳng bằng URL `x-apple.systempreferences:`), Truy cập chuỗi khoá (`com.apple.keychainaccess`), Terminal (`com.apple.Terminal`).
- Sửa luật và thời gian im lặng (15 đến 1800 giây, mặc định 120) ở tab **Agent AI** trong Cài đặt (mục thời gian im lặng và luật theo app); lưu trong UserDefaults của app.
- Gõ vào ô mật khẩu (`AXSecureTextField`) bị từ chối.

## Quyền macOS cần cấp cho Xdesk

| Quyền | Dùng để | Thiếu thì |
| --- | --- | --- |
| **Trợ năng** (Accessibility) | Chèn chuột/bàn phím, đọc cây giao diện (`xdesk_ui_tree`), đưa cửa sổ lên màn hình agent (`xdesk_launch`) | Tool báo lỗi kèm hướng dẫn |
| **Ghi màn hình** (Screen Recording) | `xdesk_screenshot` | Tool báo lỗi kèm đường dẫn cài đặt |
| **Giám sát đầu vào** (Input Monitoring) | Phát hiện bạn chạm vào màn hình agent để tự tạm dừng | Agent vẫn chạy nhưng không tự dừng khi bạn chạm; tab Agent AI hiện "Thiếu quyền Giám sát đầu vào" |

Cấp ở Cài đặt hệ thống › Quyền riêng tư & Bảo mật. Xdesk không tự cấp được các quyền này.

## Duyệt quyền trên điện thoại

Khi agent xin quyền (hoặc xin dùng một app có luật `ask`), Xdesk gửi yêu cầu `agent.approve` tới **mọi điện thoại đang xem màn hình và có quyền input**, cùng lúc với hộp thoại trên Mac. Điện thoại hiện hộp thoại "‹agent› muốn điều khiển máy Mac" kèm lý do, nút **Cho phép** / **Từ chối** (iOS và Android). **Trả lời đầu tiên thắng**: bên còn lại tự đóng, trả lời muộn bị bỏ. Hộp thoại tự đóng khi hết hạn (60 giây). Viewer chỉ xem (không có quyền input) và viewer bản cũ không nhận được yêu cầu.

## Giới hạn đã biết

- **Con trỏ thật nhảy**: agent thao tác bằng sự kiện chuột/bàn phím hệ thống nên mỗi lần agent click, con trỏ thật của bạn nhảy sang màn hình agent. Tránh dùng chuột lúc agent đang làm việc (chạm vào màn hình agent sẽ tạm dừng nó).
- **Gõ chữ/phím chỉ vào cửa sổ nằm trên màn hình agent**: nếu cửa sổ đang focus ở màn hình khác, `xdesk_type_text` và `xdesk_press_keys` từ chối; agent phải click vào cửa sổ trên màn hình agent trước.

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

## Bộ tool (15)

`xdesk_status` (chạy thật), `xdesk_request_control`, `xdesk_end_control`, `xdesk_screenshot`, `xdesk_ui_tree`, `xdesk_pointer`, `xdesk_scroll`, `xdesk_type_text`, `xdesk_press_keys`, `xdesk_run_steps`, `xdesk_launch`, `xdesk_set_workspace_size`, `xdesk_clipboard_read`, `xdesk_clipboard_write`, `xdesk_request_user_help`. Schema và annotation (`readOnlyHint`, `destructiveHint`) lấy từ `tools/list`.

### `xdesk_request_user_help`

Agent gọi khi gặp việc chỉ người dùng làm được (giải CAPTCHA, 2FA, nhập OTP, đăng nhập tài khoản). Tham số: `reason` (chuỗi, cắt còn 300 ký tự) và `timeoutSeconds` (mặc định 120, kẹp 10-600). Xdesk gửi `agent.help` tới các điện thoại đang kết nối; tool **chờ** tới khi người dùng báo đã xử lý xong trên điện thoại (thiết bị cần quyền điều khiển) rồi trả thành công, hết giờ thì trả lỗi `timeout`. Cũng là tool cần quyền điều khiển đang hiệu lực như các tool khác (ngoài ba tool đầu).

## Kiểm thử nhanh

```sh
TOKEN=...   # phần sau "Bearer "
curl -si -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  http://127.0.0.1:47810/mcp
npx @modelcontextprotocol/inspector --cli http://127.0.0.1:47810/mcp --transport http \
  --header "Authorization: Bearer $TOKEN" --method tools/list
```

## Cờ chỉ có ở bản Debug

Dành cho kiểm thử tự động, **không tồn tại ở bản Release**:

- `--enable-mcp [tệp]`: bật máy chủ MCP mà không lưu cài đặt; có `tệp` thì ghi token vào đó (quyền 0600) cho script curl.
- `--auto-approve-agent`: bỏ qua mọi hộp thoại duyệt (xin quyền và luật `ask`). Không bao giờ dùng với agent thật.

# Xdesk — Kết nối qua Tailscale / nhập địa chỉ tay (phase 09d)

Bonjour không đi qua Tailscale, nên viewer thêm host bằng địa chỉ `100.x.y.z[:cổng]` hoặc tên MagicDNS (`mac.tailnet.ts.net[:cổng]`); cổng mặc định 47800.
Viewer lưu danh sách này (`manual-hosts.json` cạnh `paired-devices.json`: `address`, `name`, `lastAddress` = IP:cổng thực lần cuối, `lastConnected`; tối đa 50). File này không phải bí mật: sửa nó chỉ đổi nơi kết nối tới, danh tính host vẫn do Noise (khoá đã ghép) xác thực.

## Host chỉ nhận qua Tailscale khi người dùng bật

Tuỳ chọn "Cho phép kết nối qua Tailscale" (menu Xdesk, **tắt mặc định**). Phát hiện: Tailscale gán cho interface `utun` của nó đúng hai dải
`100.64.0.0/10` (CGNAT) và `fd7a:115c:a1e0::/48`, nên kết nối đến có địa chỉ nguồn trong hai dải này (kể cả IPv4-mapped `::ffff:100.x`) là kết nối qua tailnet.
`ControlListener` huỷ ngay kết nối loại này khi tuỳ chọn tắt (trước khi bắt tay Noise); bật thì cho vào như LAN (vẫn phải xác thực/ghép đôi).
Chỉ áp dụng cho kết nối mới; phiên Tailscale đang chạy không bị cắt khi tắt tuỳ chọn (muốn cắt: thu hồi thiết bị hoặc dừng chia sẻ).
`InterfaceFilter.tailscaleInterfaces()` liệt kê interface `utun*` đang mang địa chỉ Tailscale để menu hiện "Qua Tailscale: ip:cổng" hoặc "Chưa thấy Tailscale trên máy này".

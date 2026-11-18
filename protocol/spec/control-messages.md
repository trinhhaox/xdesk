# Xdesk Wire v1 — Message điều khiển (JSON)

Payload của frame `kind 0x02` là một JSON object **phẳng**: `{"t":"<type>","id":<u32>, ...trường riêng}`.
`id` ghép yêu cầu/phản hồi (phản hồi dùng lại `id` của yêu cầu). Bộ giải mã bỏ qua trường lạ; `t` lạ được báo
là "unknown" và bỏ qua (tương thích tiến). JSON hỏng / thiếu trường / sai kiểu → `malformedJSON`; sai giới hạn giá trị → `invalidField`.

| `t` | Hướng | Trường | Giới hạn |
|---|---|---|---|
| `hello` | V→H | `ver` string "1.0", `caps` u32, `name` string | |
| `welcome` | H→V | `ver`, `sessionId` string, `caps` (giao) u32 | |
| `reject` | cả hai | `reason` string ("version"…), `detail` string? | |
| `display.config` | V→H | `w`,`h` u32, `scale` number, `fps` u32, `codec` "h264"\|"hevc" | w,h 1…16384; fps 1…240; scale (0,8] |
| `display.ready` | H→V | `udpPort` u16, `streamId` u16 | udpPort ≠ 0 |
| `keyframe.request` | V→H | `streamId` u16 | |
| `net.report` | V→H | `rttMs`,`lossPermille`,`jitterMs`,`recvKbps` u32 | lossPermille ≤ 1000 |
| `bitrate.set` | H↔V | `kbps` u32 | |
| `clip.offer` | cả hai | `kind` "text"\|"image", `size` u32 | |
| `clip.pull` | cả hai | `kind` "text"\|"image" | |
| `control.state` | cả hai | `owner` "agent"\|"human" | |
| `ping` | V→H | `t0` i64 (ms) | |
| `pong` | H→V | `t0` (lặp lại), `t1` (host nhận), `t2` (host gửi) i64 | |
| `bye` | cả hai | `reason` string? | |
| `input.text` | V→H | `text` string (Unicode, IME/Telex) | ≤ 4096 byte UTF-8 |

Đồng bộ đồng hồ kiểu NTP 4 mốc: viewer ghi `t3` lúc nhận pong; `offset = ((t1-t0)+(t2-t3))/2`, `rtt = (t3-t0)-(t2-t1)`.

Thêm trường tuỳ chọn ở minor mới là tương thích; trường `detail`/`reason` vắng mặt = `null` hoặc không có khoá.

## Ví dụ (dạng chuẩn của test vectors: khoá sắp xếp, không khoảng trắng)

```
{"caps":67,"id":1,"name":"Mac của Hào","t":"hello","ver":"1.0"}
{"caps":3,"id":1,"sessionId":"s-7f3a","t":"welcome","ver":"1.0"}
{"detail":"major 2 not supported","id":2,"reason":"version","t":"reject"}
{"codec":"h264","fps":60,"h":1440,"id":3,"scale":2,"t":"display.config","w":2560}
{"id":10,"t":"ping","t0":1700000000123}
```
Số thực `scale` có thể viết `2` hoặc `2.0`; bộ giải mã chấp nhận cả hai. Bộ mã hoá Swift sắp xếp khoá theo thứ tự
byte và không escape dấu `/`. Danh sách đầy đủ + frame hex: `protocol/test-vectors/control-frames.json`.

## Luồng

1. `hello` → `welcome` (hoặc `reject`). 2. `display.config` → `display.ready`. 3. Media UDP chạy; viewer gửi `net.report`
định kỳ, `keyframe.request` khi mất keyframe. `bye` đóng phiên.

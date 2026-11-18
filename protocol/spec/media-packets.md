# Xdesk Wire v1 — Gói media (UDP)

MTU an toàn: payload ≤ **1192 B**. Khi mã hoá (`crypto-handshake.md` §8) gói UDP = header 16 B (rõ, là AD) + nonce 8 B + payload mã hoá + tag 16 B, tối đa **1232 B** =
1280 (MTU IPv6 tối thiểu) − 40 (IPv6) − 8 (UDP): vừa mọi đường IPv4/IPv6, kể cả qua Tailscale (1280).

## Header 16 byte

| Offset | Kích thước | Trường | Ghi chú |
|---|---|---|---|
| 0 | u8 | `ver` | = major (1); khác → `unsupportedVersion` |
| 1 | u8 | `ptype` | bảng dưới; lạ → `unknownPacketType` |
| 2 | u16 | `streamId` | |
| 4 | u32 | `frameNo` | tăng dần, không quay vòng trong phiên |
| 8 | u16 | `fragIdx` | `< fragCnt` |
| 10 | u16 | `fragCntFlags` | bit 15 (0x8000) = keyframe; bit 0–14 = `fragCnt` (1…2048) |
| 12 | u32 | `ptsMs` | |

Lỗi: `fragCnt = 0` hoặc `fragIdx ≥ fragCnt` → `invalidFragment`; `fragCnt > 2048` → `fragmentCountTooLarge`;
payload > 1192 → `payloadTooLarge`; ít hơn 16 byte → `truncated`.

| ptype | Gói |
|---|---|
| 0x10 | video |
| 0x11 | video-parity (để dành, chưa có ngữ nghĩa) |
| 0x20 | audio |
| 0x30 | input |
| 0x31 | input-ack |
| 0x40 | nack |
| 0x50 | probe |

Gói không phân mảnh (input, ack, nack, probe) dùng `fragIdx=0`, `fragCnt=1`, `frameNo`/`ptsMs` tuỳ ý (NACK dùng 0).

## Probe (ptype 0x50)

Viewer gửi để host biết địa chỉ UDP của viewer (UDP không có bắt tay). Header + payload rỗng **hoặc** `u64 nonce` (big-endian);
độ dài khác → bỏ qua. `frameNo`/`ptsMs` = 0.
- Viewer gửi mỗi **250 ms** tới khi nhận gói đầu tiên từ host.
- Host chỉ chấp nhận probe từ **IP của peer TCP** đã bắt tay (nguồn khác bị bỏ); probe hợp lệ đầu tiên chốt địa chỉ peer và host phát sự kiện `peerConnected`. Host không trả lời probe.
Ví dụ stream 3, nonce `0123456789abcdef`: `01 50 0003 00000000 0000 0001 00000000 0123456789abcdef`.

## Video / audio: phân mảnh

Một access unit (video: AVCC chuyển Annex B khi gửi) cắt thành `ceil(len/1192)` mảnh (tối đa 2048, rỗng không hợp lệ).
Mọi mảnh của frame giữ nguyên `frameNo`, `ptsMs`, `fragCnt`, cờ keyframe. Mảnh `i` mang byte `[i*max, min((i+1)*max, len))`.

Ví dụ (`maxPayload=16`, frame 40 byte `00 01 … 27`, keyframe, stream 3, frame 42, pts 5000) → 3 gói, gói đầu:
`01 10 0003 0000002a 0000 8003 00001388 000102…0f`.

## Bộ ghép (receiver)

- Lưu mảnh theo `frameNo`; mảnh trùng bỏ qua; `fragCnt` khác nhau cho cùng `frameNo` → `inconsistentFragmentCount`.
- `watermark` = frame nhỏ nhất chưa xong; gói của frame < watermark bị bỏ. Cửa sổ 256 frame (vượt → bỏ frame cũ nhất);
  tổng byte đang ghép dở bị chặn (mặc định 32 MiB).
- Frame hoàn tất giao ngay (có thể sai thứ tự giữa các frame; tầng trên quyết định).
- Khoảng trống: frame < frame mới nhất mà chưa nhận mảnh nào.

## NACK (gói ptype 0x40)

Payload: `u8 count (1…64) | count × (u32 frameNo | u16 fragIdx)`. `fragIdx = 0xFFFF` = "chưa nhận mảnh nào của frame".
`count` ngoài 1…64 → `invalidNackCount`; độ dài không khớp → `truncated`.
Ví dụ: frame 9, mảnh 2 → `01 00000009 0002`.

Chính sách gợi ý: NACK lần đầu sau ≈ RTT/2 (20 ms), thử lại mỗi ≥ 40 ms cho cùng mục; quá 2×RTT trở lên (mặc định 500 ms)
bỏ frame và gửi `keyframe.request`. Sender giữ mảnh đã gửi để gửi lại; `0xFFFF` = gửi lại mọi mảnh.

## Input (ptype 0x30) — sự kiện cố định 28 byte

(Phase file ghi 24 B nhưng tổng các trường đã nêu là 28 B; **chốt 28 B**.)

| Offset | Kiểu | Trường |
|---|---|---|
| 0 | u8 | `kind`: 0 move, 1 down, 2 up, 3 scroll, 4 key, 5 text-ref, 6 touch |
| 1 | u8 | `button` |
| 2 | u16 | `mods` (bitmask) |
| 4 | u32 | `seq` |
| 8 | f32 | `x` (0…1 với move/down/up/touch) |
| 12 | f32 | `y` |
| 16 | f32 | `dx` |
| 20 | f32 | `dy` |
| 24 | u16 | `keyUsage` (USB HID usage) |
| 26 | u16 | `pad` (ghi 0, bỏ qua khi đọc) |

Payload gói input = 1…42 sự kiện nối nhau; độ dài không chia hết 28 / rỗng / kind lạ / NaN, ∞ / toạ độ ngoài 0…1 → `invalidInput`.
Sự kiện down/up/key cần tin cậy: người gửi giữ tới khi nhận input-ack. Ví dụ `down` trái tại (0.25, 0.75), mods 8, seq 2:
`01 01 0008 00000002 3e800000 3f400000 00000000 00000000 0000 0000`.

Ngữ nghĩa theo `kind` (không đổi bố cục byte):
- `mods` bit: 1 shift, 2 control, 4 option, 8 command, 16 capsLock, 32 fn.
- `down`/`up`: `button` 0 trái, 1 phải, 2 khác; `dx` = số lần click liên tiếp (0 hiểu là 1); host chỉ nhận `up` của nút đang giữ.
- `scroll`: `dx`,`dy` = pixel điểm của host, `dy` > 0 nội dung đi xuống; `(0, 0)` = heartbeat (không làm gì, chỉ báo còn sống).
- `key`: `button` 1 nhấn / 0 nhả; `keyUsage` = HID usage (Keyboard page 0x07).
- `seq`: down/up/key mang seq tăng dần từ 1 (cần tin cậy); move/scroll/touch để 0. Host áp dụng sự kiện cần tin cậy đúng thứ tự seq,
  đệm sự kiện đến sớm tối đa 128, bỏ trùng; khoảng trống quá 500 ms bị bỏ qua. Người gửi gửi lại mỗi 100 ms tối đa 3 lần rồi bỏ.
- Host giới hạn 1000 sự kiện/s/phiên (phần vượt bị bỏ, người gửi sẽ gửi lại nếu là sự kiện tin cậy) và nhả mọi nút/phím đang giữ
  khi phiên kết thúc hoặc khi đang giữ mà > 1 s không nhận gì: người gửi gửi heartbeat mỗi 250 ms khi còn giữ nút/phím.

**input-ack (0x31)**: payload `u32 seq` = seq lớn nhất nhận liên tục. Ví dụ seq 258 → `00000102`.
Văn bản Unicode (IME/Telex) không đi qua input UDP mà qua control `input.text`.

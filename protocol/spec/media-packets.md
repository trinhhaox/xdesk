# Xdesk Wire v1 — Gói media (UDP)

MTU an toàn: payload ≤ **1200 B** (header 16 B + tag AEAD 16 B vẫn dưới MTU 1280 của Tailscale).

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
payload > 1200 → `payloadTooLarge`; ít hơn 16 byte → `truncated`.

| ptype | Gói |
|---|---|
| 0x10 | video |
| 0x11 | video-parity (để dành, chưa có ngữ nghĩa) |
| 0x20 | audio |
| 0x30 | input |
| 0x31 | input-ack |
| 0x40 | nack |

Gói không phân mảnh (input, ack, nack) dùng `fragIdx=0`, `fragCnt=1`, `frameNo`/`ptsMs` tuỳ ý (NACK dùng 0).

## Video / audio: phân mảnh

Một access unit (video: AVCC chuyển Annex B khi gửi) cắt thành `ceil(len/1200)` mảnh (tối đa 2048, rỗng không hợp lệ).
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

**input-ack (0x31)**: payload `u32 seq` = seq lớn nhất nhận liên tục. Ví dụ seq 258 → `00000102`.
Văn bản Unicode (IME/Telex) không đi qua input UDP mà qua control `input.text`.

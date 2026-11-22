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

## Âm thanh (ptype 0x20, phase 09a)

Mac → viewer, 48 kHz stereo cố định ở v1. Mỗi gói audio **không phân mảnh** (`fragIdx=0`, `fragCnt=1`, cờ keyframe = 0) và tự đủ nghĩa: mất gói chỉ mất đúng đoạn đó, không có NACK cho audio.

| Trường header | Ý nghĩa |
|---|---|
| `streamId` | cùng stream với video |
| `frameNo` | số thứ tự gói audio, bắt đầu 0, tăng 1 mỗi gói (khác dãy `frameNo` của video) |
| `ptsMs` | thời điểm bắt đầu mẫu đầu tiên của gói trên **đồng hồ video** của host (ms kể từ lúc mở pipeline), cùng đồng hồ với `ptsMs` của video |

Payload: `u8 codec | u16 holdMs (big-endian) | data`.
- `holdMs` = số ms host giữ đoạn này từ lúc ghi (mốc của ScreenCaptureKit) tới lúc gửi, kẹp 0…65535. Viewer cộng vào ước lượng trễ đầu-cuối (không cần đồng bộ đồng hồ giữa hai máy).
- `codec 0` PCM: `data` = s16 little-endian xen kẽ L,R; độ dài chia hết cho 4 và 4…1 184 B. Host gửi 240 mẫu/kênh (5 ms, 960 B) mỗi gói → ~1,6 Mb/s kể cả header.
- `codec 1` AAC-ELD: `data` = đúng một access unit thô (không ADTS/LATM), 512 mẫu/kênh (10,67 ms); AudioSpecificConfig cố định `F8 E6 40 00` (ELD, 48 kHz, stereo, không SBR, khung 512). ~96 kb/s. Android `MediaCodec` giải được với `csd-0` = ASC này.
- Codec khác / `data` rỗng / sai độ dài → bỏ gói (đếm lỗi, không đóng kênh).
- Mỗi gói tự khai `codec` nên host đổi codec giữa phiên được (xem dưới) và viewer giải cả hai không cần báo trước.

Thương lượng (`caps`): `audioPCM` (bit 2) và `audioAACELD` (bit 3). Host chỉ đưa chúng vào `welcome` khi **thiết bị viewer đã được cấp quyền `audio`** (mặc định tắt: âm thanh hệ thống có thể chứa nội dung riêng tư) và quyền được kiểm lại mỗi giây → tắt giữa phiên là host ngừng gửi ngay. Giao của hai tập có ít nhất một codec mới có audio; host không gửi codec không có trong giao.

Chọn codec (host, `AudioCodecPolicy`): peer qua Tailscale hoặc USB (MediaOverTcp) → AAC-ELD; ngược lại PCM, và chuyển sang AAC-ELD khi ước lượng băng thông (bitrate video mà ABR đang cho phép) **< 10 Mb/s**, quay lại PCM khi **≥ 12 Mb/s** (trễ chống dao động). Chỉ chuyển giữa các codec có trong giao.

Viewer: jitter buffer mục tiêu **40 ms** (bắt đầu phát khi đủ 40 ms; thiếu → phát im lặng rồi đệm lại; dư > 100 ms → bỏ phần cũ về 40 ms; khoảng trống `frameNo` được lấp bằng im lặng). Ưu tiên trễ thấp hơn lip-sync tuyệt đối (video cũng hiển thị ngay không chờ PTS).

## Bộ ghép (receiver)

- Lưu mảnh theo `frameNo`; mảnh trùng bỏ qua; `fragCnt` khác nhau cho cùng `frameNo` → `inconsistentFragmentCount`.
- `watermark` = frame nhỏ nhất chưa xong; gói của frame < watermark bị bỏ. Cửa sổ 256 frame (vượt → bỏ frame cũ nhất);
  tổng byte đang ghép dở bị chặn (mặc định 32 MiB).
- Bộ ghép trả frame theo thứ tự hoàn tất (có thể sai thứ tự `frameNo`). Viewer đặt **cổng thứ tự** (`FrameOrderGate`) sau bộ ghép và chỉ đưa frame cho decoder theo `frameNo` tăng dần:
  - frame hoàn tất đúng thứ tự → nhả ngay (không thêm trễ);
  - frame hoàn tất khi frame đứng trước chưa xong → giữ tối đa **50 ms** (`holdBoundMs`, ≈ 1 RTT; tối đa 32 frame đang giữ);
  - keyframe hoàn tất → nhảy tới nó ngay, bỏ mọi frame đứng trước (IDR không phụ thuộc frame cũ);
  - hết hạn mà vẫn thiếu → bỏ frame thiếu, nhả các frame đang giữ theo thứ tự và gửi `keyframe.request` (giới hạn tần suất như khi mất gói);
  - nếu frame bị bỏ là keyframe (đã thấy mảnh của nó) → loại mọi P-frame cho tới keyframe kế tiếp;
  - frame có `frameNo` nhỏ hơn mốc đã nhả (đến muộn, trùng) bị bỏ. Chi phí theo số frame đang giữ, không theo khoảng nhảy `frameNo`.
- Khoảng trống: frame < frame mới nhất mà chưa nhận mảnh nào.

## NACK (gói ptype 0x40)

Payload: `u8 count (1…64) | count × (u32 frameNo | u16 fragIdx)`. `fragIdx = 0xFFFF` = "chưa nhận mảnh nào của frame".
`count` ngoài 1…64 → `invalidNackCount`; độ dài không khớp → `truncated`.
Ví dụ: frame 9, mảnh 2 → `01 00000009 0002`.

Chính sách gợi ý: NACK lần đầu sau ≈ RTT/2 (20 ms), thử lại mỗi ≥ 40 ms cho cùng mục; quá 2×RTT trở lên (mặc định 500 ms)
bỏ frame và gửi `keyframe.request`. Sender giữ mảnh đã gửi để gửi lại; `0xFFFF` = gửi lại mọi mảnh.

## Input (ptype 0x30) — sự kiện cố định 28 byte

Kích thước cố định theo code (`InputEvent.size`); `maxBatch` = ⌊1192 / 28⌋ = 42.

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

## Đường dài (Tailscale / 4G)

- MTU Tailscale 1280 → gói mã hoá ≤ 1232 B (payload ≤ 1192 B) ở đầu tài liệu đã an toàn, không cần chỉnh.
- ABR của host (`BitrateController`): khi `net.report.rttMs` > 20 ms bitrate bị chặn trần 15 000 kb/s (giảm ngay xuống 15 Mb/s nếu đang cao hơn, không tăng vượt); RTT ≤ 20 ms trở lại trần LAN 40 Mb/s.

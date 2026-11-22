# Xdesk Wire v1 — Tổng quan

Giao thức tự thiết kế của Xdesk (clean-room, không dựa trên định dạng của app khác). Tham chiếu chuẩn mở:
Noise Protocol Framework rev 34, RFC 8439, RFC 7748, H.264 Annex B / AVCC.

## Hai kênh

| Kênh | Transport | Nội dung | Định dạng |
|---|---|---|---|
| Control | TCP, tin cậy | bắt tay, cấu hình, thống kê, clipboard, ping | frame `len\|kind\|payload`, payload JSON (xem `framing.md`, `control-messages.md`) |
| Media | UDP (hoặc đóng trong TCP frame `0x04`) | video, audio, input, input-ack, NACK, probe | header 16 B + payload ≤ 1192 B (xem `media-packets.md`) |

Mã hoá: mọi frame sau handshake là AEAD (xem `crypto-handshake.md`). Chế độ `dev-plaintext` chỉ bật ở build Debug.

## Quy ước chung

- Mọi số nguyên và float: **big-endian** (network order). Float là IEEE-754 binary32.
- Giới hạn cứng (vượt → lỗi, không bao giờ crash): `len` ≤ 1 MiB; `fragCnt` ≤ 2048; payload UDP ≤ 1192 B;
  danh sách NACK ≤ 64; chunk `bulk` ≤ 64 KiB; `input.text` ≤ 4096 byte UTF-8; batch input ≤ 42 sự kiện.
- Không trường nào chứa đường dẫn file hay lệnh thực thi.
- Bộ giải mã chỉ báo lỗi có kiểu (mã lỗi ở bảng dưới); lỗi ở kênh TCP → đóng kết nối.

## Phiên bản và capability

Phiên bản `major.minor` (chuỗi `"1.0"` trong JSON; byte `ver` ở header UDP = `major`).
Major lệch → bên nhận trả `reject{reason:"version"}` rồi đóng. Minor lệch vẫn tương thích: thêm trường JSON tự do,
bên nhận bỏ qua trường/`t` lạ.

Capability là bitmask u32 (`caps`); phiên dùng giao của hai tập.

| Bit | Giá trị | Ý nghĩa |
|---|---|---|
| 0 | 0x01 | H.264 |
| 1 | 0x02 | HEVC |
| 2 | 0x04 | audio PCM |
| 3 | 0x08 | audio AAC-ELD |
| 4 | 0x10 | clipboard |
| 5 | 0x20 | media over TCP (frame 0x04) |
| 6 | 0x40 | touch input |
| 7 | 0x80 | hotReconfigure: `display.reconfigure` đổi cấu hình giữa phiên không đóng kết nối |
| 8 | 0x100 | videoPause: `video.pause` / `video.resume` (chế độ Chỉ điều khiển) |
| 9 | 0x200 | fileTransfer: truyền tệp (`file.*`) |
| 10 | 0x400 | remoteUnlock: `system.unlock` mở khoá/đánh thức Mac |
| 11 | 0x800 | mediaKeys: `media.key` phím media/âm lượng |
| 12 | 0x1000 | multiDisplay: host gửi `display.list`, `display.config.displayId` chọn màn hình |
| 13 | 0x2000 | unlockAttestation: mở khoá Mac kèm chữ ký sinh trắc học (`unlock.key`, `system.unlock.challenge`, `system.unlock{sig}`; chữ ký gắn khoá tĩnh host+viewer); host đưa bit này mỗi khi đưa `remoteUnlock` |
| 14 | 0x4000 | windowControl: `window.pick/selected/adjust` chọn, kéo, đổi cỡ, xếp cửa sổ app trên Mac; host chỉ đưa bit này khi thiết bị có quyền `input` và Mac đã cấp Accessibility |

Bit 7–12 chỉ là cờ thương lượng: bit nằm trong giao mới được dùng message tương ứng (chi tiết trong `control-messages.md`). Mac luôn đưa 7, 8, 9, 11, 12 vào `welcome`; bit 10 chỉ khi thiết bị viewer được cấp quyền mở khoá **và** Mac bật mở khoá từ xa.

## Luồng cơ bản

`Viewer hello(caps, ver) → Host welcome(sessionId, caps chung) → Viewer display.config → Host tạo màn hình ảo,
display.ready(udpPort, streamId) → UDP media ↔ input / nack / net.report`.

## Mã lỗi giải mã (dùng chung trong test vectors)

`truncated`, `invalidFrameLength`, `frameTooLarge`, `unknownFrameKind`, `unsupportedVersion`, `unknownPacketType`,
`unexpectedPacketType`, `invalidFragment`, `fragmentCountTooLarge`, `inconsistentFragmentCount`, `payloadTooLarge`,
`emptyPayload`, `invalidNackCount`, `invalidInput`, `malformedJSON`, `invalidField`.

## Test vectors

`protocol/test-vectors/{control-frames,media-headers,input-events,audio-payloads,crypto-session}.json` (`audio-payloads.json`: gói audio ptype 0x20; `crypto-session.json`: vector phiên mã hoá của Xdesk; ngoài ra `noise-*.json` là vector công khai của cacophony), sinh bởi `tools/gen-test-vectors`
(`cd tools/gen-test-vectors && swift run gen-test-vectors`). Mọi bản cài đặt (Swift, Kotlin) phải khớp: mã hoá ra đúng hex,
giải mã hex ra đúng giá trị, hex không hợp lệ ra đúng mã lỗi. JSON control so sánh theo ngữ nghĩa (thứ tự khoá tự do);
dạng chuẩn dùng khoá sắp xếp, không khoảng trắng.

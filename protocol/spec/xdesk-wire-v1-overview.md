# Xdesk Wire v1 — Tổng quan

Giao thức tự thiết kế của Xdesk (clean-room, không dựa trên định dạng của app khác). Tham chiếu chuẩn mở:
Noise Protocol Framework rev 34, RFC 8439, RFC 7748, H.264 Annex B / AVCC.

## Hai kênh

| Kênh | Transport | Nội dung | Định dạng |
|---|---|---|---|
| Control | TCP, tin cậy | bắt tay, cấu hình, thống kê, clipboard, ping | frame `len\|kind\|payload`, payload JSON (xem `framing.md`, `control-messages.md`) |
| Media | UDP (hoặc đóng trong TCP frame `0x04`) | video, audio, input, input-ack, NACK, probe | header 16 B + payload ≤ 1200 B (xem `media-packets.md`) |

Mã hoá: mọi frame sau handshake là AEAD (xem `crypto-handshake.md`). Chế độ `dev-plaintext` chỉ bật ở build Debug.

## Quy ước chung

- Mọi số nguyên và float: **big-endian** (network order). Float là IEEE-754 binary32.
- Giới hạn cứng (vượt → lỗi, không bao giờ crash): `len` ≤ 1 MiB; `fragCnt` ≤ 2048; payload UDP ≤ 1200 B;
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

## Luồng cơ bản

`Viewer hello(caps, ver) → Host welcome(sessionId, caps chung) → Viewer display.config → Host tạo màn hình ảo,
display.ready(udpPort, streamId) → UDP media ↔ input / nack / net.report`.

## Mã lỗi giải mã (dùng chung trong test vectors)

`truncated`, `invalidFrameLength`, `frameTooLarge`, `unknownFrameKind`, `unsupportedVersion`, `unknownPacketType`,
`unexpectedPacketType`, `invalidFragment`, `fragmentCountTooLarge`, `inconsistentFragmentCount`, `payloadTooLarge`,
`emptyPayload`, `invalidNackCount`, `invalidInput`, `malformedJSON`, `invalidField`.

## Test vectors

`protocol/test-vectors/{control-frames,media-headers,input-events}.json`, sinh bởi `tools/gen-test-vectors`
(`cd tools/gen-test-vectors && swift run gen-test-vectors`). Mọi bản cài đặt (Swift, Kotlin) phải khớp: mã hoá ra đúng hex,
giải mã hex ra đúng giá trị, hex không hợp lệ ra đúng mã lỗi. JSON control so sánh theo ngữ nghĩa (thứ tự khoá tự do);
dạng chuẩn dùng khoá sắp xếp, không khoảng trắng.

# Phase 02 — Đặc tả giao thức Xdesk Wire v1 + thư viện XdeskWire

## Context
- Phụ thuộc: phase 01. Tự thiết kế hoàn toàn (clean-room) — không tham chiếu định dạng của app khác.
- Chuẩn tham khảo công khai: Noise Protocol Framework rev 34, RFC 8439 (ChaCha20-Poly1305), RFC 7748 (X25519), H.264 Annex B / AVCC.

## Overview
- Ưu tiên: P1 · Trạng thái: in review · Effort: 2d
- Viết spec trong `protocol/spec/`, sinh test vectors, cài codec Swift (`XdeskWire`). Codec Kotlin làm ở phase 07 dùng chung vectors.

## Key insights
- Tách 2 kênh: **control** (TCP, tin cậy, JSON) và **media** (UDP, nhị phân cố định, NACK). Input đi trên UDP (độ trễ thấp, mất một sự kiện move không sao) nhưng sự kiện "down/up/key" có seq + ACK nhẹ để không kẹt phím.
- JSON cho control vì hiếm và dễ debug (Codable / kotlinx.serialization); nhị phân cho luồng nóng vì cấp phát thấp.
- Chừa chỗ crypto từ đầu: mọi frame sau handshake là `AEAD(payload)`; chế độ `dev-plaintext` chỉ bật bằng cờ build Debug.

## Requirements
- Có version `major.minor` + bitmask capability; major lệch → `Reject{reason: "version"}`.
- Hỗ trợ: video (H.264/HEVC), input, audio PCM/AAC-ELD, clipboard, thống kê mạng, yêu cầu keyframe, đổi độ phân giải.
- Định dạng endian: big-endian (network order) mọi trường số.

## Architecture
### Control channel (TCP)
- Frame: `u32 len | u8 kind | payload[len-1]`; `kind`: 0x01 Handshake, 0x02 Control(JSON), 0x03 Bulk (clipboard ảnh, chunk ≤ 64 KiB). Giới hạn `len` ≤ 1 MiB, vượt → đóng kết nối.
- Message JSON `{ "t": "<type>", "id": <u32>, ...}`; type: `hello`, `welcome`, `reject`, `display.config` (w, h, scale, fps, codec), `display.ready` (udpPort, streamId), `keyframe.request`, `net.report` (rtt, loss‰, jitter, recvKbps), `bitrate.set`, `clip.offer`, `clip.pull`, `control.state` (agent/human), `ping`/`pong` (đồng bộ đồng hồ kiểu NTP 4 mốc), `bye`.
### Media channel (UDP, MTU an toàn 1200 B payload)
- Header 16 B: `u8 ver | u8 ptype | u16 streamId | u32 frameNo | u16 fragIdx | u16 fragCnt | u32 ptsMs`. `ptype`: 0x10 video, 0x11 video-parity (để dành, YAGNI), 0x20 audio, 0x30 input, 0x31 input-ack, 0x40 nack.
- Video: 1 access unit (AVCC → chuyển Annex B khi gửi) cắt thành mảnh; cờ keyframe trong bit cao `fragCnt`. Receiver thiếu mảnh > 1 RTT/2 → gửi NACK (danh sách `frameNo,fragIdx`, tối đa 64); quá 2×RTT hoặc keyframe mất → `keyframe.request`.
- Input event (cố định 24 B): `u8 kind (move/down/up/scroll/key/text-ref/touch) | u8 button | u16 mods | u32 seq | f32 x | f32 y | f32 dx | f32 dy | u16 keyUsage | u16 pad`; toạ độ chuẩn hoá 0…1 theo khung video. `text` (IME, tiếng Việt Telex) đi control JSON `input.text` để giữ Unicode đầy đủ.
- Dự phòng TCP: cùng header, đóng trong frame `kind 0x04 MediaOverTcp` (dùng cho USB/usbmux và mạng chặn UDP).
### Crypto (đặc tả chi tiết ở phase 06, khung ở đây)
- Handshake Noise `XX` (ghép đôi) / `IK` (kết nối lại), suite `25519_ChaChaPoly_SHA256`; sau handshake dẫn xuất khoá riêng cho TCP và UDP bằng HKDF(`"xdesk v1 tcp"`/`"xdesk v1 udp"`).
- UDP: nonce = `u32 0 | u64 packetCounter`; cửa sổ chống replay 1024; tag 16 B nối cuối.
### Data flow
`Viewer hello(caps, ver) → Host welcome(sessionId, caps chung) → Viewer display.config → Host tạo màn hình ảo, display.ready(udpPort) → UDP media ↔ input/nack/net.report`.

## Related code files
- Tạo: `protocol/spec/xdesk-wire-v1-overview.md`, `framing.md`, `control-messages.md`, `media-packets.md`, `crypto-handshake.md` (khung), `protocol/test-vectors/{control-frames,media-headers,input-events}.json`.
- Tạo Swift: `XdeskWire/ControlFrame.swift`, `ControlFrameCodec.swift`, `ControlMessage.swift`, `MediaHeader.swift`, `InputEvent.swift`, `Packetizer.swift`, `Reassembler.swift`, `NackTracker.swift`, `ProtocolVersion.swift`; tests tương ứng.

## Implementation steps
1. Viết spec (mỗi file < 200 dòng), có ví dụ hex.
2. Viết bộ sinh test vectors (Swift script trong `tools/gen-test-vectors/`), commit file JSON kết quả.
3. Cài codec + test round-trip + test với vectors.
4. Packetizer/Reassembler: test mất gói ngẫu nhiên (seed cố định), đảo thứ tự, trùng lặp, mảnh > fragCnt (từ chối).
5. Fuzz đơn giản: 10k frame ngẫu nhiên vào decoder không crash (len sai, JSON hỏng).

## Todo
- [x] 5 file spec
- [x] test vectors
- [x] XdeskWire codec + Packetizer/Reassembler/NackTracker
- [x] Unit + fuzz test xanh

## Success criteria
- `swift test --filter XdeskWireTests` xanh, coverage XdeskWire ≥ 85% dòng.
- Reassembler phục hồi 100% frame khi loss 5% có NACK mô phỏng (test xác định).
- Spec đủ để người khác viết bản Kotlin mà không hỏi lại (review chéo bởi code-reviewer).

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Spec thiếu trường → phải tăng major sớm | TB×TB | capability bitmask + JSON thêm trường tự do; review spec trước khi code 03 |
| Phân mảnh IP nếu payload > MTU (Tailscale MTU 1280) | TB×Cao | payload 1200 B cố định, header + tag tính vào |

## Security
- Giới hạn kích thước mọi trường, từ chối fragCnt > 2048, len > 1 MiB; JSON parse trong do/catch, không crash.
- Không có trường nào chứa đường dẫn file hay lệnh thực thi.

## Next steps
- Phase 03 dùng XdeskWire cho host/viewer.

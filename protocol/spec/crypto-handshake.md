# Xdesk Wire v1 — Mã hoá và bắt tay (KHUNG — phase 06 hoàn thiện)

Trạng thái: **khung**, chưa đủ để cài đặt. Phase 06 điền chi tiết và thêm test vectors mật mã.

## Quyết định đã chốt

- Bắt tay Noise `XX` (ghép đôi lần đầu) và `IK` (kết nối lại), suite `Noise_*_25519_ChaChaPoly_SHA256`
  (Noise Protocol Framework rev 34; X25519 RFC 7748; ChaCha20-Poly1305 RFC 8439).
- Bắt tay đi trong frame TCP `kind 0x01`.
- Sau bắt tay dẫn xuất hai khoá riêng bằng HKDF: info `"xdesk v1 tcp"` và `"xdesk v1 udp"`.
- Sau bắt tay mọi frame `0x02/0x03/0x04` và mọi gói UDP là `AEAD(payload)`; chế độ `dev-plaintext` chỉ ở build Debug.
- UDP: nonce 12 byte = `u32 0 | u64 packetCounter` (big-endian); tag 16 B nối cuối gói; cửa sổ chống replay 1024.
- Ghép đôi: QR (token 32 B) hoặc so mã 6 số (SAS có commitment).

## Phase 06 cần chốt

- Prologue/payload của handshake, định dạng static key lưu Keychain/Keystore.
- Quy tắc xoay khoá, counter TCP, AAD (có gồm header UDP hay không — đề xuất: có).
- Vector mật mã (handshake đầy đủ với khoá cố định, AEAD từng gói).
- Ảnh hưởng tới kích thước: tag 16 B nằm ngoài giới hạn payload 1200 B của `media-packets.md`.

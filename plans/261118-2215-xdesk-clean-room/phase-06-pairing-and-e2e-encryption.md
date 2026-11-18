# Phase 06 — Ghép đôi + mã hoá đầu-cuối

## Context
- Phụ thuộc: 05 (luồng đầy đủ đã chạy plaintext). Khung crypto đã chừa ở spec 02.
- Chuẩn: Noise rev 34 (`XX`, `IK`), X25519, ChaCha20-Poly1305, SHA-256, HKDF. Apple: CryptoKit. Android (phase 07): JCA `XDH` + `ChaCha20-Poly1305` (API 31+, cần xác nhận) hoặc thư viện nhỏ đã kiểm định nếu thiếu.

## Overview
- Ưu tiên: P1 · pending · 5d
- Mọi kết nối Release bắt buộc mã hoá + xác thực thiết bị. Ghép đôi 1 lần, lần sau tự kết nối.

## Key insights
- Mỗi thiết bị có khoá tĩnh X25519 (Mac/iOS: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; Android: lưu mã hoá bằng khoá Android Keystore). Fingerprint = 8 byte đầu SHA-256(pub) hiển thị dạng nhóm.
- Ghép đôi **QR** (iOS/Android quét màn hình Mac): QR = `xdesk://pair?h=<host pub b64>&t=<token 32B>&a=<addr>` → Noise `XXpsk3` với psk = token (entropy cao, dùng 1 lần, hết hạn 2 phút).
- Ghép đôi **so mã 6 số** (Mac viewer không quét được QR): Noise `XX` + SAS = 6 chữ số từ `HKDF(handshakeHash)`; chống MITM "mài khoá" bằng commitment: bên khởi tạo gửi `H(ephemeral)` trước, lộ ephemeral sau. Cả hai màn hình hiện mã, người dùng bấm "Khớp" trên Mac host.
- Kết nối lại: Noise `IK` (viewer biết khoá host) — 1 RTT; host từ chối khoá viewer không có trong danh sách đã ghép.
- UDP: khoá riêng từ split(), nonce đếm 64-bit, cửa sổ replay 1024; rekey mỗi 2^32 gói hoặc 1 giờ (`rekey` qua control).
- Tự cài Noise thay vì thêm dependency: phạm vi nhỏ (2 pattern), kiểm bằng test vectors công khai của Noise (cacophony) — phải chạy xanh cả Swift và Kotlin.

## Requirements
- Ghép đôi ≤ 30 s thao tác; quên thiết bị (thu hồi) ở Mac host → kết nối ngay bị cắt.
- Overhead CPU mã hoá < 3% ở 40 Mb/s.
- Release build: không có đường plaintext (kiểm bằng test + grep cờ `devPlaintext` chỉ trong `#if DEBUG`).

## Architecture
```
[DeviceIdentityStore(Keychain)] → static key
Viewer ──Noise msg1──► Host
       ◄─msg2────────        (XX/XXpsk3/IK)
       ──msg3────────►  → split() → TcpCipher, UdpCipher(HKDF labels)
[PairedDevicesStore v1] {id, name, pub, role, createdAt, lastSeen, permissions:{view,input,clipboard,audio}}
```
- Data flow: khoá host xuất hiện trong TXT Bonjour (`id` = fingerprint) để viewer biết host nào đã ghép.

## Related code files (tạo)
- `XdeskCrypto/`: `NoiseHandshakeState.swift`, `NoiseSymmetricState.swift`, `NoiseCipherState.swift`, `NoisePatterns.swift`, `ShortAuthString.swift`, `ReplayWindow.swift`, `DatagramCipher.swift`, `DeviceIdentityStore.swift`, `PairedDevicesStore.swift`.
- `mac-app/Sources/Pairing/`: `PairingWindow.swift`, `PairingQrView.swift`, `SasConfirmView.swift`, `PairedDevicesSettings.swift`.
- `ios-app/Sources/Pairing/`: `QrScannerView.swift`, `SasView.swift`.
- `protocol/spec/crypto-handshake.md` (hoàn thiện), `protocol/test-vectors/noise-*.json`.

## Implementation steps
1. Cài Noise symmetric/cipher/handshake + test vectors cacophony cho `XX`, `XXpsk3`, `IK`.
2. DatagramCipher + ReplayWindow (test: trùng, cũ, ngoài cửa sổ, đảo thứ tự).
3. Tích hợp vào ControlConnection/UdpMediaChannel; bỏ plaintext ở Release.
4. UI ghép đôi QR (Mac hiện, iOS quét) và SAS (Mac↔Mac).
5. Danh sách thiết bị đã ghép + thu hồi + quyền từng thiết bị.
6. Rekey + xử lý lỗi giải mã (đếm lỗi > 50/s → đóng phiên).

## Todo
- [ ] Noise + vectors
- [ ] DatagramCipher + replay
- [ ] Tích hợp transport
- [ ] UI QR + SAS
- [ ] Quản lý thiết bị + quyền
- [ ] Rekey + giới hạn lỗi

## Success criteria
- Test vectors Noise xanh 100%.
- Wireshark trên LAN: không thấy chuỗi/khung H.264 rõ (entropy payload ≈ 8 bit/byte), không có start code `00 00 00 01`.
- Thu hồi iPad ở Mac → iPad mất kết nối ≤ 1 s, kết nối lại bị từ chối.
- Thử MITM bằng thiết bị thứ 3 giả host cùng tên Bonjour → viewer cảnh báo khoá khác, không kết nối.

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Lỗi tự cài crypto | TB×Cao | chỉ dùng primitive CryptoKit/JCA, tự cài phần máy trạng thái Noise, vectors chính thức, code-reviewer + review bảo mật riêng |
| Android API thiếu X25519/ChaCha ở máy cũ | TB×TB | minSdk 31; nếu JP1 < 31 → dùng Tink/BouncyCastle (hỏi user) |
| Mất Keychain (cài lại máy) | Thấp×TB | ghép lại đơn giản; không cần backup khoá |

## Security
- Token QR dùng 1 lần, hết hạn 2 phút, không log. Không log khoá/nonce. So sánh MAC/token constant-time.
- Quyền mặc định thiết bị mới: view + input; clipboard/audio tắt cho đến khi người dùng bật.

## Backwards compat
- Bản 03–05 chỉ là Debug nội bộ → không cần migration. `PairedDevicesStore` có `schemaVersion=1` để nâng cấp sau.

# Xdesk Wire v1 — Mã hoá, bắt tay và ghép đôi

Trạng thái: **đã cài đặt** ở cả hai nền tảng (Swift: `apple/Packages/XdeskKit/Sources/XdeskCrypto`; Kotlin: `android/crypto`), cùng chạy xanh `noise-*.json` và `crypto-session.json`.
Vector cho từng byte: `protocol/test-vectors/noise-*.json` (cacophony, công khai) và `crypto-session.json` (của Xdesk, sinh bởi `tools/gen-test-vectors`).

## 1. Thuật toán

- Noise Protocol Framework **rev 34** (noiseprotocol.org), suite `25519_ChaChaPoly_SHA256`: X25519 (RFC 7748), ChaCha20-Poly1305 (RFC 8439), SHA-256, HKDF theo §4.3 của Noise (HMAC-SHA256).
- Chỉ dùng primitive của CryptoKit/JCA; máy trạng thái Noise tự cài (không có thư viện Noise).
- **Nonce ChaCha 12 byte** (mọi nơi): `4 byte 0x00 | counter u64 little-endian` (đúng chuẩn Noise). Trường nonce *mang trên đường truyền* (UDP) là `u64 big-endian` như mọi trường wire khác.
- Kết quả DH toàn số 0 (điểm bậc thấp) → huỷ bắt tay. So sánh token/commitment/tag dùng so sánh thời gian hằng.

## 2. Danh tính thiết bị

- Mỗi thiết bị có một khoá tĩnh X25519 (32 byte), sinh lần đầu, **không bao giờ rời thiết bị**. Mac/iOS: Keychain generic password trong **data-protection keychain** (`kSecUseDataProtectionKeychain`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable=false`; app phải ký bằng Team ID — thiếu entitlement thì thư viện báo `dataProtectionKeychainUnavailable` hoặc, ở chế độ `preferred`, rơi về login keychain cũ và báo qua `backend`). Android: lưu mã hoá bằng khoá Android Keystore (`android/app/.../identity/KeystoreIdentityStore.kt`). Mất khoá = ghép đôi lại.
- **Fingerprint** = 8 byte đầu `SHA-256(pub)`, hex HOA, nhóm 4 ký tự nối bằng `-`: `AB12-CD34-EF56-7890`. Cũng là `id` của thiết bị đã ghép và giá trị `id` trong TXT Bonjour của host. Ví dụ pub = 32 byte 0 → `6668-7AAD-F862-BD77`.
- `PairedDevicesStore` (JSON, `schemaVersion` 1): `{schemaVersion, devices:[{id, name, pub (base64url), role: 0 host|1 viewer, createdAt, lastSeen?, permissions:{view,input,clipboard,audio}}], mac}`.
  `mac` = base64url `HMAC-SHA256(key, "xdesk v1 paired-devices" 0x00 | JSON chuẩn của {schemaVersion, devices})` (JSON chuẩn = bộ mã hoá sortedKeys, ngày ISO-8601 giây; không có trường `mac`), `key` = 32 B ngẫu nhiên trong Keychain cùng lớp truy cập với khoá tĩnh. File sai/thiếu MAC → coi là rỗng, bật cờ `integrityFailure` (fail-closed; UI phải báo). Tra cứu thiết bị luôn theo **khoá công khai đầy đủ 32 B** (so sánh hằng thời gian); `id` 64 bit chỉ để hiển thị. Thêm khoá có `id` trùng nhưng khác khoá → lỗi `deviceIdCollision`. File ghi 0600 (thư mục 0700). Mặc định thiết bị mới: view + input bật, clipboard + audio tắt. File lạ phiên bản hoặc hỏng → báo lỗi, không tự xoá.
  `devices[].lastAddress` (tuỳ chọn, `host:port`): viewer lưu địa chỉ gần nhất kết nối được tới host đã ghép để tự chọn IK khi người dùng nhập tay; chỉ là gợi ý, không dùng để xác thực. Mỗi thiết bị có hai danh sách riêng: `paired-devices.json` (viewer được vào máy này, role viewer) và `known-hosts.json` (host máy này đã ghép, role host), mỗi danh sách một khoá MAC trong Keychain.
  Khi MAC sai: file được chuyển thành `paired-devices.json.tampered` **trước lần ghi kế tiếp** (không mất bằng chứng); cờ `integrityNoticePending` giữ tới khi UI xác nhận.

## 3. Chọn pattern

Viewer luôn là **initiator**, host là **responder**. Prologue = ASCII `xdesk-wire-v1` (13 byte) cho mọi pattern.

| Tình huống | Pattern | Ràng buộc |
|---|---|---|
| Ghép đôi bằng QR (viewer quét màn hình host) | `Noise_XXpsk3_25519_ChaChaPoly_SHA256`, psk = token 32 B của QR | viewer kiểm khoá tĩnh host (từ message 2) = `h` trong QR, sai → huỷ |
| Ghép đôi so mã (không quét được QR, ví dụ Mac↔Mac) | `Noise_XX_25519_ChaChaPoly_SHA256` + SAS (mục 5) | host chỉ ghi thiết bị sau khi người dùng bấm "Khớp" |
| Kết nối lại | `Noise_IK_25519_ChaChaPoly_SHA256` | viewer biết khoá host đã ghép; host từ chối khoá không có trong danh sách |

Mọi kết nối Release bắt buộc một trong ba pattern. Không có đường plaintext ngoài `devPlaintext` (chỉ `#if DEBUG`).

## 4. Frame bắt tay (TCP kind 0x01)

Payload frame `0x01` = `u8 type | body` (`HandshakeFrame`):

| type | Tên | Body |
|---|---|---|
| 0x00 | begin | `u8 wireMajor=1 | u8 pattern` (1 = XX, 2 = XXpsk3, 3 = IK). Initiator gửi đầu tiên |
| 0x01 | commit | 32 B cam kết SAS; **chỉ XX**, gửi ngay sau `begin`, trước message 1 |
| 0x02 | noise | một message Noise (≤ 65 535 B) |
| 0x03 | usbHello | 32 B khoá công khai của host. **Chỉ đường hầm USB** (vai TCP đảo, xem `framing.md`): host (TCP-client) gửi trước mọi thứ để viewer (TCP-server) chọn đúng khoá IK trong danh sách host đã ghép. Không xác thực gì (khoá công khai không bí mật); body ≠ 32 B → đóng |

Host bác `begin` có `wireMajor` khác 1 hoặc pattern lạ, và bác mọi frame sai thứ tự/ sai type → đóng kết nối. Host **không** trả lời trước khi `begin` hợp lệ; XX không bắt đầu xử lý message 1 nếu chưa có `commit`. Timeout toàn bộ phần mật mã của bắt tay: 30 s; **mỗi message tối đa 5 s** (quá hạn → đóng). Host giới hạn bắt tay chưa xác thực: **tối đa 2 mỗi IP nguồn**, tối đa 4 đồng thời; đầy thì **đuổi kết nối chưa xác thực cũ nhất**. Kết nối chưa xác thực chỉ được gửi/nhận frame `0x01`; frame `0x02-0x04` rõ trước khi xong bắt tay → đóng.

Ví dụ `begin` XXpsk3: `000102` (payload frame 0x01 → `00000004 01 000102`).

### Payload ứng dụng trong message Noise (`HandshakePayload`)

`u8 ver=1 | u8 role (0 host, 1 viewer) | u8 flags (bit0 = có nonce SAS) | u8 nameLen (≤ 64) | name UTF-8 | [16 B sasNonce nếu bit0]`.
Độ dài phải khớp tuyệt đối, UTF-8 hợp lệ, flags chưa định nghĩa phải = 0; sai → huỷ.

| Pattern | Message 1 (I→R) | Message 2 (R→I) | Message 3 (I→R) |
|---|---|---|---|
| XX | payload rỗng | hello (role host, tên) | hello (role viewer, tên, **sasNonce**) |
| XXpsk3 | rỗng | hello host | hello viewer (không nonce) |
| IK | hello viewer (mã hoá dưới `es`) | hello host | — (2 message) |

Message 1 của XX/XXpsk3 không được mã hoá nên payload phải rỗng; **cả bên viết lẫn bên đọc** từ chối payload khác rỗng (`invalidHandshakePayload`).

### Luồng và kiểm tra của host

- **XXpsk3**: host đang hiển thị QR có token hiệu lực mới nhận `begin(XXpsk3)` (không có token hiệu lực → đóng). Dùng `psk = token`. Viewer **ghim khoá host**: khoá tĩnh nhận ở message 2 phải bằng `h` của QR trước khi gửi message 3, lệch → viewer huỷ, không gửi gì thêm. Sau message 3 hợp lệ, host gọi `consume(token)`: thất bại (token đã dùng/hết hạn) → huỷ. Rồi host **bắt buộc hỏi người dùng** ("Cho phép '<tên>' điều khiển máy này?"); chỉ khi đồng ý mới ghi thiết bị (quyền mặc định view + input, người dùng có thể chỉnh lúc duyệt) và gửi `pair.result{accepted:true}`; từ chối/quá 60 s → `pair.result{accepted:false}` rồi đóng. Token vô hiệu sau **5 lần bắt tay hỏng** và **đổi mỗi 20 s khi host đang có phiên chạy** (người xem màn hình, kể cả viewer chỉ-xem hay ghi hình, không kịp dùng); không dùng thì hết hạn sau 2 phút. Cửa sổ QR phải loại khỏi capture của chính host.
- **XX + SAS**: xem mục 5. Sau message 3 phiên ở trạng thái *tạm*: kênh đã mã hoá nhưng host chưa nhận message nào từ viewer và chưa có media; host gửi `pair.result` (`control-messages.md`) sau khi người dùng quyết định. Host ghi thiết bị chỉ khi người dùng bấm "Khớp"; viewer thấy `pair.result{accepted:false}` hoặc đóng kết nối = bị từ chối.
- **IK**: sau message 1 host biết khoá tĩnh viewer; không có trong danh sách (so sánh khoá đầy đủ 32 B) → đóng TCP, không trả lời (không lộ gì). Có → gửi message 2 và áp dụng quyền đã lưu. Phiên chỉ được coi là **đã xác thực** sau **frame mã hoá hợp lệ đầu tiên** của viewer (bắt buộc là `hello`): chỉ khi đó mới cập nhật `lastSeen`, báo "đã kết nối" và bật capture/encode. Message 1 có thể bị phát lại nên không đủ để chứng minh viewer đang hiện diện; kẻ phát lại không có `e` của viewer nên không gửi được frame hợp lệ và bị đóng bởi timeout `hello`.
- Thu hồi thiết bị ở host (xoá khỏi danh sách) → đóng ngay mọi phiên của thiết bị đó (≤ 1 s, theo dõi thay đổi của danh sách chứ không chờ UI); kết nối lại bị IK từ chối.

Viewer: IK tới host mà khoá đã đổi (host cài lại) sẽ bị đóng như "không nhận ra" → UI gợi ý ghép đôi lại; nếu TXT Bonjour `id` của host cùng tên mà khác fingerprint đã lưu → cảnh báo khoá khác, không kết nối.

## 5. SAS — so mã 6 số có cam kết (chỉ XX)

Mục tiêu: người dùng so 6 số trên hai màn hình; kẻ MITM không thể "mài" khoá để hai mã trùng.

**Vấn đề**: SAS 6 số chỉ 2^20 giá trị; nếu kẻ MITM còn chọn được một phần đầu vào của mã *sau khi* thấy mã phía bên kia, nó mài phần đó tới khi hai mã trùng (≈10^6 lần thử, dưới 1 giây nếu cache được mọi thứ trước payload).

**Thiết kế** (kiểu ZRTP/Bluetooth): cam kết nonce trước, mã chỉ phụ thuộc dữ liệu đã chốt trước khi nonce lộ.

1. Initiator sinh `sasNonce` 16 B ngẫu nhiên, ephemeral `e` và có sẵn static `s`.
2. Gửi `commit = SHA-256("xdesk v1 sas-commit" | e.pub | s.pub | sasNonce)` (ASCII nhãn + 32 + 32 + 16 B) trong frame `commit`, **trước** message 1.
3. Chạy XX; `sasNonce` đi trong payload message 3 (mã hoá). Mỗi bên lưu `h2` = handshake hash **ngay sau message 2** (bên viết message 2 lưu sau khi viết, bên đọc lưu sau khi đọc; hai giá trị bằng nhau). Thư viện: `NoiseHandshakeState.messageTwoHash`.
4. Sau message 3, responder dựng lại commit từ `e` (message 1), `s` (message 3), `sasNonce` và so sánh thời gian hằng với commit đã nhận; lệch → huỷ (`commitment mismatch`).
5. Mỗi bên tính `code = u64_BE(HKDF-SHA256(ikm = sasNonce, salt = h2 (32 B), info = "xdesk v1 sas", 8 B)) mod 1 000 000`, hiển thị `NNN NNN` (đệm số 0 đầu). **Không** dùng hash sau message 3: payload message 3 (tên thiết bị…) do initiator chọn tự do và không được cam kết nên không được ảnh hưởng mã.

**Lý do chống MITM** (M = kẻ giữa, I = viewer, R = host). Mã phía R là `f(n_M, h2_R)`. `n_M` bị khoá bởi commit *trước khi* R gửi message 2; `h2_R` chứa `e_R` ngẫu nhiên của R nên M không biết/không chọn được khi cam kết, và sau message 2 mọi thứ trong `h2_R` đã chốt, nội dung message 3 không đổi được mã (test hồi quy: đổi payload message 3 → mã không đổi). Mã phía I là `f(n_I, h2_I)` với `n_I` chỉ lộ ở message 3, tức sau khi M đã chốt message 2 của nó, nên với M `code_I` đồng đều ngẫu nhiên. Vậy M thắng với xác suất ≤ 10^-6 mỗi lần thử, không mài được. (Phiên bản trước dùng hash sau message 3 và bị phá: M mài tên thiết bị trong message 3 tới khi `code_R = code_I`, xem báo cáo rà soát 261119.) Mỗi lần thử hỏng người dùng thấy hai mã khác nhau và bấm "Không khớp"; host giới hạn 3 lần ghép SAS hỏng / 10 phút.

Chỉ initiator cam kết; responder không cần vì mọi đóng góp của R vào `h2` (gồm `e_R`) đã có trước khi initiator lộ nonce.

## 6. Dẫn xuất khoá phiên

Sau message cuối, `split()` của Noise cho `k1` (initiator→responder) và `k2` (responder→initiator). `h` = handshake hash. Bốn khoá, mỗi khoá `HKDF-SHA256(ikm, salt = h, info, 32 B)`:

| Khoá | ikm | info (ASCII) |
|---|---|---|
| TCP i→r | k1 | `xdesk v1 tcp i2r` |
| TCP r→i | k2 | `xdesk v1 tcp r2i` |
| UDP i→r | k1 | `xdesk v1 udp i2r` |
| UDP r→i | k2 | `xdesk v1 udp r2i` |

Initiator gửi bằng `i2r` và nhận bằng `r2i`; responder ngược lại. TCP và UDP không bao giờ dùng chung khoá; mỗi hướng một khoá. Khoá Noise thô `k1/k2` không dùng trực tiếp.

**Rekey** (một chiều): `K' = HKDF-SHA256(ikm = K, salt = rỗng, info = "xdesk v1 rekey", 32 B)`.

## 7. Kênh TCP sau bắt tay

Frame `0x02/0x03/0x04` mã hoá. Khung vẫn là `len | kind | payload` (`framing.md`) nhưng `payload = ciphertext | tag 16 B`:

- `len = 1 + plaintext + 16`, vẫn ≤ 1 048 576 → plaintext tối đa 1 048 559 B; bulk ≤ 65 536 B giữ nguyên (tính trên plaintext).
- Nonce = bộ đếm frame u64 mỗi hướng, bắt đầu 0, tăng sau mỗi frame (kể cả `0x04`); không mang trên đường truyền (TCP có thứ tự).
- **AD = `u32 len BE | u8 kind`** nên kind và độ dài được xác thực.
- Frame `0x01` không còn hợp lệ sau bắt tay; frame `0x01` sau đó → đóng.
- `MediaOverTcp (0x04)` chứa nguyên gói media (header + payload) được mã hoá bằng khoá TCP, **không** dùng khoá UDP.
- Giải mã lỗi (tag sai, thứ tự sai) → đóng kết nối ngay, vì luồng không thể đồng bộ lại.
- **Rekey TCP** (mỗi hướng độc lập): bên gửi gửi control `{"id":0,"t":"rekey"}` (`control-messages.md`) là frame cuối dưới khoá cũ rồi đổi khoá gửi (nonce về 0); bên nhận sau khi giải mã `rekey` đổi khoá nhận (message này không chuyển lên tầng trên). Kích hoạt mỗi ≥ 1 giờ hoặc sau 2^32 frame.

## 8. Gói UDP sau bắt tay

```
+----------------+-----------------+-----------------+----------+
| header 16 B    | nonce u64 BE    | ciphertext      | tag 16 B |
| (rõ, là AD)    | epoch<<32|ctr   | = len(payload)  |          |
+----------------+-----------------+-----------------+----------+
```

- Header media (`media-packets.md`) **không mã hoá** và là AD → không sửa được; payload mã hoá. Tổng thêm `8 + 16 = 24` byte; datagram tối đa `16 + 1192 + 24 = 1232` B (vừa MTU IPv6 tối thiểu, `media-packets.md`).
- `nonce = epoch u32 << 32 | counter u32`; counter đếm từ 0 mỗi epoch, tăng cho **mọi gói gửi**. Gói gửi lại (đáp NACK) phải **mã hoá lại** với counter mới, không gửi lại cùng byte (sẽ bị coi là replay).
- Bên nhận kiểm theo thứ tự: độ dài ≥ 40; chọn epoch (hiện tại, ngay trước, hoặc 1…**4** epoch mới hơn, xem dưới; khác → `unknownEpoch`); **cửa sổ replay 1024** theo counter của epoch đó (bitmap; trùng → `replayed`, cũ hơn `highest − 1023` → `outsideReplayWindow`); giải mã AEAD với AD = header; **chỉ khi thành công** mới đánh dấu cửa sổ/ chuyển epoch. Gói tag sai không đốt counter.
- Epoch mới hơn `e + k` (`1 ≤ k ≤ 4`) mở được ngay: bên nhận dẫn xuất thử `rekey^k(K_e)`, giải mã AEAD, và **chỉ khi tag đúng** mới chuyển sang epoch đó (cửa sổ replay mới) và giữ epoch ngay trước nó (`e + k − 1`, cửa sổ mới nếu `k ≥ 2`) cho gói đến muộn; epoch cũ hơn nữa bị bỏ. Vậy bên gửi im lặng rekey theo giờ hoặc mất cả epoch vẫn được bên nhận theo kịp sau tối đa 3 epoch bị bỏ qua. Nhảy `k ≥ 5` → `unknownEpoch`; phục hồi bằng control **`rekey.resync`** (`control-messages.md`): (a) bên gửi UDP báo `{epoch, ask:false}` mỗi khi nó rekey; (b) bên nhận thấy ≥ 3 lỗi `unknownEpoch` và 2 s không có gói hợp lệ thì gửi `{epoch: epoch nhận hiện tại, ask:true}` (tối đa 1 lần/5 s), bên kia trả `{epoch: epoch gửi hiện tại, ask:false}`. Khi nhận `ask:false` (đã xác thực qua TCP) bên nhận kéo khoá nhận lên đúng epoch đó (dẫn xuất tối đa 64 epoch, cửa sổ replay mới, bỏ epoch trước). Chi phí DoS của gói giả epoch xa chỉ ≤ 4 HKDF + 1 AEAD, không đổi trạng thái.
- **Rekey UDP**: bên gửi tự quyết, gọi `rekey()` khi `needsRekey` (≥ 2^32 − 65 536 gói trong epoch **hoặc** epoch sống ≥ 3600 s); cứng: refuse gửi ở 2^32 gói/epoch. Bên nhận tự theo kịp khi thấy gói epoch mới xác thực được — không cần message control cho UDP.
- Gói UDP mã hoá tối thiểu 40 B; ngắn hơn → bỏ.

## 9. Mã QR ghép đôi

`xdesk://pair?h=<b64url host pub>&t=<b64url token>&a=<host:port>[&a=<host:port>…]`

- `h`: 32 B khoá tĩnh host; `t`: token 32 B (cũng là psk); base64url **không đệm** (RFC 4648 §5). `a`: 1…4 địa chỉ ứng viên `host:port` (IPv6 dạng `[addr]:port`, nên %-encode `[` `]`), thứ tự ưu tiên. Mỗi địa chỉ phải đúng cú pháp: IPv4 chấm thập phân, `[IPv6]` (không zone `%`), hoặc hostname RFC 1123 (nhãn 1…63 ký tự `[A-Za-z0-9-]`, không đầu/cuối `-`, tổng ≤ 253, nhãn cuối không thuần số); cổng chỉ chữ số, 1…65535; tổng ≤ 255 B; sai một địa chỉ → từ chối cả URI. Tham số lạ bỏ qua; trùng `h`/`t`, thiếu, sai độ dài, scheme/host khác `xdesk`/`pair`, có path → từ chối.
- Token: 32 B từ RNG hệ thống, **hết hạn 2 phút**, một tại một thời điểm (phát token mới vô hiệu token cũ), dùng một lần, không log. Ví dụ trong `crypto-session.json` → `pairing`.

## 10. Xử lý lỗi và giới hạn

| Tình huống | Hành động |
|---|---|
| Lỗi giải mã TCP (bất kỳ) | đóng kết nối |
| Lỗi UDP: tag sai, `unknownEpoch`, quá ngắn | bỏ gói và đếm (chỉ để đo); **không bao giờ đóng phiên vì gói chưa xác thực** (ai trên LAN cũng gửi được rác vào cổng UDP). Replay/quá cũ không tính là lỗi |
| Không có gói UDP hợp lệ nào suốt **10 s** | báo `linkLost` → viewer báo phiên hỏng, host đóng phiên. Mỗi bên gửi `probe` giữ liên lạc 2 s/lần nên màn hình tĩnh không bị cắt nhầm |
| Bắt tay lỗi (auth, DH, payload, commit, khoá không khớp QR) | đóng TCP; không gửi chi tiết cho đối tác |
| Hết nonce (2^64 − 1 TCP, 2^32 mỗi epoch UDP) | đóng/ rekey; không bao giờ lặp nonce |

Mọi lỗi mật mã là `CryptoError` (Swift), kể cả điểm bậc thấp (CryptoKit tự ném → gói thành `invalidDiffieHellman`; kiểm DH toàn số 0 vẫn bắt buộc cho cổng Kotlin/JCA); không log khoá, nonce, token, psk, hash.

## 11. Ghi chú Android

`android/crypto` dùng JCA, không thư viện ngoài: ChaCha20-Poly1305, SHA-256, HmacSHA256; HKDF tự cài trên HMAC. X25519 qua `XDH` của JCA (API 33+); nơi JCA không có `XDH` (API 31–32) thì dùng bản thuần Kotlin `X25519Fallback` (RFC 7748, không rẽ nhánh theo bit bí mật). Kiểm DH toàn số 0 vẫn bắt buộc ở cả hai đường. Test Kotlin chạy `noise-*.json`, `crypto-session.json` và một phiên đầu-cuối (`EndToEndSessionTest`).

## 12. Quyết định đã chốt

- MTU: `maxPayload` = 1192 → datagram mã hoá ≤ 1232 B (đủ IPv6 1280).
- Tên message control đã chốt trong `control-messages.md`: `rekey`, `rekey.resync`, `pair.result`.

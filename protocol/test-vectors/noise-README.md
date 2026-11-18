# Noise test vectors (noise-*.json)

Nguồn: bộ vector công khai của dự án **cacophony** (Haskell Noise implementation)
`https://raw.githubusercontent.com/centromere/cacophony/master/vectors/cacophony.txt` (tải 2026-11-19, 944 vector).
Giấy phép: public domain ("free and unencumbered software", Unlicense) — xem `noise-cacophony-LICENSE.txt`.

Chỉ giữ các vector cho suite của Xdesk (`25519_ChaChaPoly_SHA256`); mỗi pattern có đúng 1 vector trong nguồn:

| File | protocol_name |
|---|---|
| `noise-xx.json` | `Noise_XX_25519_ChaChaPoly_SHA256` |
| `noise-xxpsk3.json` | `Noise_XXpsk3_25519_ChaChaPoly_SHA256` |
| `noise-ik.json` | `Noise_IK_25519_ChaChaPoly_SHA256` |

Nội dung giữ nguyên (chỉ đổi định dạng JSON). Cách dùng: `init_*`/`resp_*` cho prologue, khoá tĩnh, ephemeral (khoá riêng, cố định),
psk; `messages[i]` lần lượt là message của initiator (i chẵn) và responder (i lẻ); các message đầu là message bắt tay,
các message sau là message truyền tải (CipherState từ split, AD rỗng). `handshake_hash` là h sau bắt tay.

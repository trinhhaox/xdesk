# Xdesk Wire v1 — Framing kênh control (TCP)

```
+----------+--------+----------------------+
| len u32  | kind u8| payload (len-1 byte) |
+----------+--------+----------------------+
```

`len` = 1 + độ dài payload (tính cả byte `kind`), big-endian. Điều kiện: `1 ≤ len ≤ 1 048 576`.

| kind | Tên | Payload |
|---|---|---|
| 0x01 | Handshake | `u8 type | body` (begin/commit/noise), xem `crypto-handshake.md` §4 |
| 0x02 | Control | JSON UTF-8 (xem `control-messages.md`) |
| 0x03 | Bulk | chunk nhị phân (clipboard ảnh), ≤ 65 536 B |
| 0x04 | MediaOverTcp | một gói media nguyên vẹn (header + payload, xem `media-packets.md`); dự phòng USB/mạng chặn UDP |

kind khác → `unknownFrameKind`.

Sau bắt tay, payload của `0x02/0x03/0x04` là `ciphertext | tag 16 B` (`len = 1 + plaintext + 16`, AD = `len | kind`), xem `crypto-handshake.md` §7.

## Quy tắc bộ giải mã luồng

1. Chưa đủ 4 byte: chờ thêm.
2. Đủ 4 byte: kiểm `len` ngay (`len = 0` → `invalidFrameLength`; `len > 1 MiB` → `frameTooLarge`), không chờ nhận hết payload.
3. Đủ 5 byte: kiểm `kind`.
4. Đủ `4 + len` byte: trả frame; byte thừa thuộc frame kế tiếp.
5. Bất kỳ lỗi nào → đóng kết nối.

## Ví dụ hex

| Frame | Hex |
|---|---|
| Handshake, payload `aa bb cc` | `00000004 01 aabbcc` |
| Bulk, payload `00` | `00000002 03 00` |
| MediaOverTcp, payload rỗng | `00000001 04` |
| Control `{"id":10,"t":"ping","t0":1700000000123}` | `00000028 02 7b226964223a31302c2274223a2270696e67222c227430223a313730303030303030303132337d` |

Frame sai: `0000000002` (len=0) → `invalidFrameLength`; `0010000102` (len = 1 MiB + 1) → `frameTooLarge`;
`0000000109` → `unknownFrameKind`.

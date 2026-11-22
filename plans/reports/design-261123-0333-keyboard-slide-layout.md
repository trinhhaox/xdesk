# Thiết kế lại chế độ Bàn phím + Slide & Số (dọc / ngang) — iOS + Android

Vấn đề: khi xoay ngang, header (tên Mac, khoá, ngắt) + lưới 5 chế độ (2 hàng) + thanh "Bàn phím Mac | Gõ văn bản" chiếm ~½ chiều cao → phím bị ép, chồng lên nhau, khó gõ/nhìn. Slide & Số cũng không tính tới hướng màn hình.

## Nguyên tắc chung (3 chế độ điều khiển: Chuột, Bàn phím, Slide & Số)
- **Thanh trên gọn 1 hàng** thay cho header + lưới 5 nút:
  - Trái: tên Mac (1 dòng, cắt …).
  - Giữa: nút chọn chế độ dạng **menu** (icon + tên chế độ hiện tại ▾) mở danh sách 5 chế độ. Không còn lưới 2 hàng.
  - Phải: Khoá Mac, Ngắt kết nối (icon).
  - Chiều cao: dọc 48 pt/dp, ngang 36 pt/dp. Tôn trọng safe area / tai thỏ / thanh điều hướng (ngang: chừa 2 bên).
- Nội dung phía dưới chiếm **toàn bộ** phần còn lại; không cuộn.
- Không phần tử nào được chồng lên nhau: mọi bố cục tính từ kích thước thật còn lại (GeometryReader / BoxWithConstraints), có kích thước tối thiểu cho phím; thiếu chỗ thì ẩn bớt hàng phụ chứ không ép nhỏ dưới mức tối thiểu.
- Phím tối thiểu: cao 34 pt/dp ở ngang, 40 ở dọc; chữ trên phím ≥ 13 sp/pt (F-row ≥ 11). Khoảng cách giữa phím 4.
- Nền tối hiện tại giữ nguyên (design tokens trong docs/design-tokens.md).

## Bàn phím
- Chuyển "Bàn phím Mac | Gõ văn bản" từ thanh segmented to bản thành **nút gạt nhỏ trong thanh trên** (icon ⌨ / Aa), không chiếm hàng riêng.
- **Ngang (bàn phím Mac):** bàn phím chiếm toàn bộ vùng dưới thanh trên, rộng tràn (trừ safe area).
  - Nếu chiều cao đủ cho 6 hàng × 34 + khoảng cách: hiện cả hàng F (thấp hơn, 70% chiều cao phím thường).
  - Nếu không đủ: **ẩn hàng F**, thêm phím `fn` ở đầu hàng dưới cùng (thay vị trí… hoặc thu hẹp control) — giữ `fn` thì hàng số tạm thời hiện F1–F12/esc thay cho ` 1–0 - = (như bàn phím laptop). Hàng dưới: fn 1, control 1.25, option 1.25, command 1.5, space ~4.5, command, option, mũi tên. Tổng vẫn 15 đơn vị.
- **Dọc (bàn phím Mac):** chia màn hình:
  - Trên (~40%): **vùng di chuột** (trackpad dùng lại TrackpadInterpreter: 1 ngón di, chạm = click, 2 ngón cuộn/chuột phải) — để vừa gõ vừa trỏ, đúng kiểu "điện thoại thành bàn phím + chuột".
  - Dưới (~60%): bàn phím Mac đầy đủ, hàng F thấp. Nếu thiếu chiều cao thì vùng chuột co lại trước (tối thiểu 120), sau đó mới ẩn hàng F (dùng fn).
- **Gõ văn bản** (giao diện cũ) giữ chức năng; ở ngang: ô nhập + nút Gửi một hàng, các phím đặc biệt (⌘⌥⌃⇧ esc tab space ⌫ ↩ ⌘C ⌘V ⌘A ←↑↓→) thành 2 hàng tràn rộng; ở dọc: như hiện tại nhưng nằm dưới thanh trên gọn.
- Hiệu ứng nhấn: phím sáng + phóng nhãn nhẹ (bubble nhỏ phía trên phím với chữ cái khi dọc; ngang không cần bubble).

## Slide & Số
3 nhóm: **Trình chiếu** (F5 Bắt đầu, Esc Kết thúc, ◀ Trước, ▶ Sau [to nhất], Space, ⌘Z), **Media** (⏮ ⏯ ⏭, 🔇, 🔉, 🔊), **Bàn phím số** (7 8 9 / , 4 5 6 * , 1 2 3 - , 0 . = + , ⌫ ↩).
- **Dọc:** xếp dọc: Trình chiếu (◀ ▶ là 2 nút lớn cạnh nhau cao ~72, các nút phụ 1 hàng) → Media 1 hàng 6 nút → Bàn phím số lưới 4 cột chiếm phần còn lại (ô vuông tối đa, không cuộn).
- **Ngang:** 3 cột cạnh nhau: Trình chiếu (cột trái ~35%: ◀ ▶ lớn theo chiều dọc + nút phụ) | Media (cột giữa hẹp ~20%, nút xếp lưới 2×3) | Bàn phím số (cột phải ~45%, lưới 4 cột). Tất cả vừa khít chiều cao, không cuộn.
- Nút có nhãn chữ ngắn dưới icon (dọc); ngang có thể chỉ icon + tooltip/nhãn nhỏ nếu thiếu chỗ.
- Bàn phím số gửi HID keypad thật (Keypad 0–9 0x59–0x62, . 0x63, + 0x57, - 0x56, * 0x55, / 0x54, = 0x67, Enter 0x58) — đồng nhất iOS/Android (Android hiện gửi dạng text → sửa).

## Chung cho cả hai nền tảng
- Đổi hướng không gây gửi lại `display.config` (đã sửa: chế độ điều khiển dùng màn hình gốc).
- Không kẹt phím khi xoay: xoay trong lúc giữ phím → nhả hết (releaseAll) trước khi dựng lại bố cục.
- Kiểm tra trên các kích thước: iPhone 14 Pro Max (430×932), iPhone SE (375×667), Android 720×1600 @~2.0 (JP1, ~360×800 dp). Không phần tử nào chồng/tràn ở cả 2 hướng.

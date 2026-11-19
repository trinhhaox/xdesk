# Xdesk design tokens

Một nguồn duy nhất cho giao diện iOS (`apple/ios-app/Sources/Pairing/BrandPalette.swift`) và Android
(`android/app/src/main/kotlin/vn/xox/xdesk/app/ui/theme/XdeskTheme.kt`). iOS là bản tham chiếu đã được duyệt; Android dựng lại 1:1 từ cùng bảng này.
Đổi một giá trị ở đây thì sửa cả hai file trên. Màu thương hiệu xem thêm `brand-guide.md`.

## Giao diện (Appearance)

Cả hai app mặc định **Tối**. Cài đặt → "Giao diện": `Tối` (mặc định) | `Sáng` | `Theo hệ thống`. Lưu cục bộ
(iOS `UserDefaults` `xdesk.appearance`, Android `SharedPreferences` `xdesk_appearance`). iOS áp bằng `.preferredColorScheme` (Theo hệ thống = `nil`),
Android bằng `XdeskTheme(appearance)` cộng nền cửa sổ tối ngay khi khởi động (không loé trắng).

## Màu

| Token | Tối | Sáng | Dùng cho |
|---|---|---|---|
| background | `#101218` | `#F6F7FA` | Nền màn hình |
| surface (nhóm) | `#1C1C1E` | `#FFFFFF` | Thẻ nhóm hàng (iOS inset-grouped) |
| separator | `#38383A` | `#D8D8DC` | Đường kẻ giữa hàng |
| label | `#FFFFFF` | `#000000` | Chữ chính |
| secondaryLabel | `#98989F` | `#6C6C70` | Dòng phụ, tiêu đề nhóm, chú thích |
| tertiaryLabel | `#5C5C61` | `#B4B4B9` | Mũi tên ›, giá trị mờ |
| primary | `#5B8CFF` | `#2457E6` | Biểu tượng, liên kết, dấu chọn |
| primaryFill | `#2F6BFF` | `#2F6BFF` | Nền nút chính, chữ trắng trên đó |
| accent | `#18C29C` | `#0B7A63` | "Đã ghép", trạng thái tốt |
| warning | `#F5A524` | `#8A5A00` | "Chưa ghép", khoá đã đổi |
| danger | `#FF6B6B` | `#C62828` | Lỗi, xoá |
| segmentTrack | `#2C2C2E` | `#EEEEF0` | Nền nút phân đoạn |
| segmentSelected | `#636366` | `#FFFFFF` | Đoạn đang chọn |
| toolbarPill | `#2B2E38` | `#E4E7F0` | Viên thuốc chứa nút Tìm lại + Cài đặt |
| overlay | `#101218` @ 90% | `#101218` @ 90% | Lớp phủ trên video (cố định, không đổi theo giao diện) |
| primaryOnOverlay | `#5B8CFF` | `#5B8CFF` | Nhấn trên lớp phủ tối |

iOS dùng màu ngữ nghĩa của hệ thống (`secondarySystemGroupedBackground`, `secondaryLabel`, ...) có giá trị trùng bảng trên (đo từ ảnh chụp); Android dùng đúng hex.

## Chữ (pt trên iOS = sp trên Android)

| Vai trò | Cỡ | Đậm |
|---|---|---|
| largeTitle ("Xdesk") | 34 | Bold |
| navTitle ("Cài đặt" giữa thanh) | 17 | SemiBold |
| sectionHeader | 17 | SemiBold, secondaryLabel |
| body (tiêu đề hàng) | 17 | Regular |
| subheadline (dòng phụ) | 15 | Regular, secondaryLabel |
| footnote (chú thích dưới nhóm) | 13 | Regular, secondaryLabel |
| badge ("Đã ghép") | 13 | Bold |
| primaryButton | 17 | SemiBold |

## Khoảng cách và bo góc

- Lề màn hình (thẻ cách mép): 18. Đệm trong thẻ: 20 ngang. Tiêu đề nhóm thụt 18 so với thẻ (cách mép 36).
- Khoảng giữa các nhóm: 28. Tiêu đề → thẻ: 8. Thẻ → chú thích: 8.
- Bo góc thẻ nhóm: 26. Nút chính và viên thuốc toolbar: viên thuốc (bo tròn hết).
- Hàng tối thiểu 52 (đích chạm ≥ 48). Biểu tượng đầu hàng: khung 28, cách chữ 12. Đường kẻ bắt đầu từ chữ (thụt 40) khi hàng có biểu tượng.

## Biểu tượng SF Symbol ↔ Material

| Ý nghĩa | SF Symbol | Android |
|---|---|---|
| Quét QR | `qrcode.viewfinder` | `QrScanIcon` (tự vẽ) |
| Tìm lại | `arrow.clockwise` | `Icons.Filled.Refresh` |
| Cài đặt | `gearshape` | `Icons.Outlined.Settings` |
| Máy Mac | `desktopcomputer` | `XdeskIcons.Monitor` |
| Mũi tên › | `chevron.right` | `XdeskIcons.Chevron` |
| Menu hàng | `ellipsis.circle` | `XdeskIcons.EllipsisCircle` |
| Nhập địa chỉ | `network` | `XdeskIcons.Globe` |
| Cáp USB | `cable.connector` | `XdeskIcons.Cable` |
| Giống màn hình Mac | `macbook` | `XdeskIcons.Laptop` |
| Vừa với điện thoại | `iphone.gen3` | `XdeskIcons.Phone` |
| Tối ưu thao tác | `hand.point.up.left` | `XdeskIcons.HandTap` |
| Dấu chọn | `checkmark` | `Icons.Filled.Check` |
| Tối / Sáng / Hệ thống | `moon.fill` / `sun.max` / `circle.lefthalf.filled` | `XdeskIcons.Moon` / `Sun` / `HalfCircle` |
| Quay lại | `chevron.left` | `Icons.AutoMirrored.Filled.ArrowBack` |
| Xoá | `trash` | `Icons.Filled.Delete` |

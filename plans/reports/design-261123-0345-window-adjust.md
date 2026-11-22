# Chỉnh cửa sổ Mac từ điện thoại (kéo, thu phóng, đổi kích thước) — spec dùng chung

Mục tiêu: ở các chế độ có hình (Chiếu Mac, Màn phụ; đặc biệt "Tối ưu thao tác" khi màn ảo nhỏ), người dùng chọn một cửa sổ app trên Mac rồi kéo di chuyển, chụm/mở 2 ngón để đổi kích thước, hoặc bấm nhanh các kiểu xếp (vừa màn hình, nửa trái/phải, giữa, khôi phục).

## Giao thức (bản 1.0, thêm cap — không đổi major)
- Cap bit 14 `windowControl` = `0x4000`. Host chỉ cấp khi thiết bị có quyền `input` và Mac đã cấp Accessibility. Viewer chỉ hiện tính năng khi cap được thương lượng.
- Toạ độ trong tin nhắn = toạ độ điểm của **luồng video viewer đang xem** (cùng hệ với input con trỏ tuyệt đối: 0..w/scale, 0..h/scale của display.config đang chạy; host tự quy đổi sang toạ độ màn hình Mac như input).
- V→H `window.pick {x, y}`: chọn cửa sổ trên cùng tại điểm (bỏ qua cửa sổ của Xdesk, Dock, menu bar, desktop). Host trả H→V `window.selected`.
- H→V `window.selected {ok, windowId?, app?, title?, frame?:{x,y,w,h}, resizable?, message?}`: frame theo cùng hệ toạ độ viewer; `ok:false` + `message` khi không có cửa sổ (ví dụ "Không có cửa sổ ở đây").
- V→H `window.adjust {windowId, op, ...}` với `op`:
  - `move` + `dx, dy` (điểm, cộng dồn từ frame hiện tại của host),
  - `resize` + `w, h` (kích thước tuyệt đối mong muốn, điểm; host giữ tâm cửa sổ hoặc giữ góc trên-trái khi tâm làm tràn màn),
  - `preset` + `preset ∈ fill | left | right | center | restore` (fill = phủ vùng hiển thị trừ menu bar/Dock; left/right = nửa màn; center = 70% màn, đặt giữa; restore = frame trước lần chỉnh đầu tiên trong phiên).
  - Host trả lại `window.selected` với frame mới (để viewer vẽ khung chọn). Lỗi (cửa sổ đã đóng, app không cho đổi cỡ) → `ok:false` + message tiếng Việt.
- Giới hạn: tối đa 60 `window.adjust`/giây (viewer gộp theo khung hình); host kẹp frame trong màn hình đang chiếu, kích thước tối thiểu 200×150, tối đa = vùng hiển thị.
- `windowId` là id do host cấp (số), chỉ có hiệu lực trong phiên; host giữ map id → AXUIElement.
- Kết thúc phiên: không tự khôi phục các cửa sổ người dùng đã chỉnh tay (khác WindowFitter tự co). Nhưng WindowFitter không được co lại cửa sổ đã chỉnh tay trong phiên (đánh dấu "user-adjusted" để fitter bỏ qua, và bỏ khỏi danh sách khôi phục của fitter).

## Host (Mac)
- Dùng AX: `AXUIElementCopyElementAtPosition` trên system-wide → leo lên tới `kAXWindowRole`; đọc/ghi `kAXPositionAttribute`, `kAXSizeAttribute`; `kAXSizeAttribute` settable để biết `resizable`. Tái dùng `AXWindowAccess.swift` nếu hợp.
- Quy đổi toạ độ giống input (dùng chung mapper của HostInputService cho display đang chiếu).
- Áp dụng trên main actor/serial queue, gộp các adjust liên tiếp (chỉ áp frame mới nhất mỗi ~16 ms).
- Log ngắn (không log tiêu đề cửa sổ ở mức public).

## Viewer (iOS + Android, giống nhau)
- Chỉ ở chế độ có hình, khi cap `windowControl` có. Nút "Chỉnh cửa sổ" trong menu nổi (icon `macwindow` / tương đương) và trong dock nhanh khi fit = "Tối ưu thao tác".
- Bật chế độ chỉnh cửa sổ (overlay trên video, input chuột thường tạm tắt):
  1. Gợi ý trên cùng: "Chạm vào cửa sổ muốn chỉnh".
  2. Chạm 1 lần → `window.pick` → vẽ khung viền xanh quanh frame trả về + tên app.
  3. 1 ngón kéo trong khung → di chuyển (gửi `move` theo delta, gộp mỗi khung hình); viền theo tay ngay (dự đoán phía viewer), chỉnh lại theo frame host trả về.
  4. 2 ngón chụm/mở → đổi kích thước theo tỉ lệ chụm, quanh tâm (`resize`). Kéo 4 góc khung (tay cầm tròn 28 pt/dp) → đổi kích thước theo góc.
  5. Chạm vào cửa sổ khác → chọn cửa sổ đó.
  6. Thanh dưới: [Vừa màn hình] [◧ Trái] [◨ Phải] [▣ Giữa] [↺ Khôi phục] [Xong]. Không cửa sổ nào được chọn thì các nút xám.
  7. Zoom video của viewer (pinch ở "Giống màn hình Mac") tắt khi đang chỉnh cửa sổ; thoát chế độ thì trở lại như cũ.
- Haptic nhẹ khi chọn được cửa sổ và khi chạm biên.
- `window.selected ok:false` → toast message.
- Rời chế độ có hình / ngắt kết nối → tự thoát chế độ chỉnh.

## Kiểm thử
- Wire: codec Swift + Kotlin, vector trong protocol/test-vectors/control-frames.json (regenerate bằng tools/gen-test-vectors), coverage test hai bên.
- Host: test thuần cho quy đổi toạ độ, kẹp frame, preset, gộp adjust (không cần AX thật).
- Viewer: test thuần cho gesture → op (kéo → move delta, chụm → resize, góc → resize), kẹp kích thước tối thiểu phía viewer.

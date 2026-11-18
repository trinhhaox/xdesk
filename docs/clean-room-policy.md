# Chính sách clean-room

Xdesk được viết độc lập hoàn toàn. Mục tiêu: không có dòng mã, tên gọi, chuỗi, tài nguyên hay định dạng dữ liệu nào được vay mượn từ ứng dụng tham khảo.

## Danh sách cấm

- Không mở, đọc, grep, liệt kê hay sao chép bất cứ thứ gì trong thư mục dự án `meowdisplay` của máy dev.
- Không giải nén, dịch ngược, chạy `strings`/`otool`/`nm` hay phân tích gói ứng dụng Yosei (`/Applications/Yosei.app`) hoặc bất kỳ binary nào của nó.
- Không dùng lại tên hàm, tên kiểu, chuỗi giao diện, icon, âm thanh, màu sắc hay bố cục của các ứng dụng đó.
- Không vay mượn định dạng gói tin, mã lệnh, thứ tự trường hay hằng số giao thức; giao thức `xdesk-wire` tự thiết kế trong `protocol/spec/`.
- Không nhờ công cụ AI/agent đọc các nguồn bị cấm để "tóm tắt" rồi đưa kết quả vào dự án.

## Nguồn được phép

- Tài liệu công khai của Apple, Google, IETF và các chuẩn mở (RFC, tài liệu framework).
- Thư viện mã nguồn mở có giấy phép tương thích, ghi rõ trong PR và `docs/code-standards.md`.
- Mã và đặc tả do chính dự án Xdesk viết.

## Checklist cho mỗi PR

- [ ] Không tên, chuỗi, asset hay định dạng nào vay mượn từ ứng dụng tham khảo.
- [ ] Mọi hằng số giao thức có nguồn gốc trong `protocol/spec/` hoặc chuẩn công khai.
- [ ] Phụ thuộc mới có giấy phép được ghi lại.
- [ ] Người viết xác nhận chưa xem nguồn bị cấm trong lúc làm PR này.

## Nếu lỡ đọc nguồn bị cấm

1. Dừng ngay, không tiếp tục viết phần liên quan.
2. Ghi lại sự việc (ngày, nguồn, phần đã thấy) vào `plans/reports/`.
3. Người khác, chưa từng xem nguồn đó, viết lại phần bị ảnh hưởng từ đặc tả; bản của người đã xem bị loại bỏ.

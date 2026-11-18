# latency-probe

Đo độ trễ glass-to-glass của luồng Xdesk (Mac host → Mac viewer) mà không cần camera.

- `latency-probe clock`: cửa sổ trên màn hình ảo "Xdesk" vẽ đồng hồ ms + mã 32 bit (vạch tím 2 ô, 1 ô trống,
  32 ô bit MSB trước, trắng = 1; mã = `UInt32(epoch ms)`), vẽ lại mỗi nhịp màn hình.
- Viewer chạy với `--latency-overlay` (Debug): vạch xanh + 32 ô bit của giờ host ước lượng (`ClockSync`) ở góc cửa sổ.
- `latency-probe measure ảnh.png...`: tìm hai vạch trong cùng một ảnh chụp, độ trễ = mã xanh − mã tím
  (ảnh chụp đồng thời nên thời điểm chụp không ảnh hưởng). Sai số ≈ ±1 nhịp màn hình (16,7 ms) mỗi đầu.
- `./run.sh [N]`: chạy trọn quy trình trên một Mac qua loopback và in p50/p95.

Giới hạn: loopback không có độ trễ mạng; số đo là chi phí capture + encode + UDP cục bộ + decode + hiển thị.
Đo Wi-Fi/Ethernet thật cần hai máy (đồng hồ đã đồng bộ qua ping/pong) và vẫn nên đối chiếu quay slow-mo 240 fps.

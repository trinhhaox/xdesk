# Latency phase 03b — Mac host → Mac viewer (loopback, 1 máy)

Ngày: 2026-11-19 · Máy: Apple Silicon, macOS 27, build Debug · 1920×1200@60, H.264 low-latency, 10 Mb/s khởi điểm.

## Cách đo
`tools/latency-probe/run.sh 80`: app Xdesk (host + viewer cùng tiến trình, loopback 127.0.0.1) + `latency-probe clock` vẽ đồng hồ ms + mã 32 bit
lên màn hình ảo "Xdesk"; viewer (`--latency-overlay`) vẽ mã giờ host ước lượng (ClockSync) cạnh khung video; `screencapture` chụp màn hình chính
80 lần, `latency-probe measure` giải mã hai mã trong cùng ảnh → độ trễ = mã viewer − mã probe trong video.

## Kết quả (thật)
| Lần | n | min | p50 | p95 | max |
|---|---|---|---|---|---|
| 1 | 80 | 33 ms | 35 ms | 52 ms | 69 ms |
| 2 | 80 | 16 ms | 34 ms | 52 ms | 52 ms |

Số đo lượng tử theo nhịp màn hình (16,7 ms): sai số ≈ ±1 nhịp mỗi đầu. Viewer báo fps 53–57, mất khung 0‰, RTT điều khiển 0 ms, offset đồng hồ 0 ms (cùng máy).
CPU toàn tiến trình (host + viewer, Debug, đang vẽ lại toàn khung): ~17% một lõi.

## Giới hạn / chưa đo
- Loopback: không có độ trễ mạng; đây là chi phí capture + encode + UDP cục bộ + decode + hiển thị. Đạt mục tiêu p50 < 50 ms, p95 < 80 ms **ở điều kiện loopback**.
- Chưa đo Wi-Fi 5 GHz/Ethernet hai máy, 3% loss, ngắt Wi-Fi 5 s, 30 phút ổn định, 100 lần kết nối/ngắt (Instruments Leaks).
- Chưa đối chiếu slow-mo 240 fps.

# Xdesk — Âm thanh Mac → thiết bị và kết nối cáp USB (phase 09a + 09c)

Giao thức: `protocol/spec/media-packets.md` (mục Âm thanh), `framing.md` (đường hầm USB), `crypto-handshake.md` §4 (`usbHello`).

## 1. Âm thanh

- Mac ghi âm thanh hệ thống bằng ScreenCaptureKit trên đúng luồng của màn hình ảo (`capturesAudio`, `excludesCurrentProcessAudio`, 48 kHz stereo) — không cần thêm quyền ngoài "Ghi màn hình". Xdesk bỏ qua âm của chính nó nên không bị vọng khi Mac vừa là host vừa là viewer.
- **Quyền riêng từng thiết bị: `audio`, MẶC ĐỊNH TẮT** (Cửa sổ "Thiết bị đã ghép" → ô "Âm thanh"). Lý do: âm thanh hệ thống có thể chứa cuộc gọi/nhạc/thông báo riêng tư; cùng mức nhạy cảm với clipboard nên cùng chính sách mặc định tắt. Host chỉ đưa cờ `audioPCM`/`audioAACELD` vào `welcome` khi quyền bật và kiểm lại mỗi giây (tắt giữa phiên → ngừng gửi ≤ 1 s).
- Codec: PCM s16 trên LAN (~1,6 Mb/s); AAC-ELD (AudioToolbox, 96 kb/s, 512 mẫu/khung) khi đi Tailscale/USB hoặc ước lượng băng thông < 10 Mb/s (quay lại PCM khi ≥ 12 Mb/s). Viewer giải cả hai theo từng gói.
- Viewer (Mac + iOS): `AVAudioEngine` + jitter buffer 40 ms. iOS dùng `AVAudioSession` loại `.playback` (phát cả khi gạt im lặng), IO buffer 5 ms. Android: `AudioTrack` `PERFORMANCE_MODE_LOW_LATENCY` (PCM) + `MediaCodec` AAC-ELD (`csd-0` = `F8E64000`).
- Số liệu viewer: `ViewerSession.audioStats` (gói, độ sâu jitter buffer, underrun, trễ thiết bị) và `audioLatencyEstimateMs` = host giữ + RTT/2 + jitter buffer + thiết bị phát.

### "Chỉ phát trên thiết bị" (tắt loa Mac khi đang stream)

Menu Xdesk → "Chỉ phát âm thanh trên thiết bị (tắt loa Mac)", mặc định tắt. Cách làm: tắt tiếng thiết bị ra mặc định qua CoreAudio (`kAudioDevicePropertyMute`). SCK ghi âm TRƯỚC bước tắt tiếng của thiết bị nên viewer vẫn nghe đủ (đã đo: biên độ bíp không đổi khi loa bị tắt).

Cách khôi phục an toàn (`OutputMuteGuard`):
1. Chỉ tắt khi loa đang BẬT tiếng. Người dùng đã tự tắt sẵn thì không đụng, và không bao giờ bật lại hộ.
2. Ghi `~/Library/Application Support/Xdesk/audio-mute-restore.json` (UID thiết bị) **trước** khi tắt; xoá sau khi bật lại.
3. Đếm số phiên audio: phiên đầu tắt, phiên cuối (hoặc thoát app bình thường) bật lại.
4. Crash / kill -9 / mất điện: lần mở Xdesk kế tiếp thấy file và bật lại đúng thiết bị đó ngay lúc khởi động.
5. Khôi phục theo UID đã tắt, không theo "thiết bị mặc định hiện tại" (đã đổi tai nghe giữa chừng vẫn đúng).
Giới hạn: nếu app chết rồi người dùng không mở lại Xdesk thì loa vẫn tắt tới khi tự bật (hoặc mở lại Xdesk một lần). Thiết bị không có công tắc mute (một số HDMI/USB) thì tính năng không có tác dụng và không thay đổi gì.

### Đo độ trễ miệng–tai

`tools/audio-latency/beep.swift` phát bíp 1 kHz vào mốc hẹn; chạy Xdesk Debug với `--audio-report` (và env `XDESK_AUDIO_TRACE=1` để host in giờ SCK giao âm). Kết quả loopback trên máy dev (PCM, 22–70 s): SCK giao đoạn âm thanh sau 27–47 ms, tới viewer thêm 1–3 ms; cộng jitter buffer (~20–60 ms) → khoảng 60–100 ms tới loa. AAC-ELD thêm ~5–20 ms.

## 2. USB iPhone/iPad (usbmuxd)

```
Mac (host, TCP-client) ──usbmuxd /var/run/usbmuxd── cáp ── iPhone (viewer, TCP-server, cổng 47801, chỉ loopback)
   Noise responder                                          Noise initiator (IK)
```

- Mac mở `UsbDeviceMonitor` (plist `Listen`): cắm/rút hiện trong menu ngay (vài chục ms; usbmuxd chỉ báo thiết bị USB, lọc bỏ thiết bị Wi-Fi).
- Menu "Phát qua USB tới iPhone/iPad …<8 ký tự cuối serial>" gửi `Connect{DeviceID, PortNumber=47801}`; app Xdesk trên máy phải đang mở (nếu không: "cổng bị từ chối").
- Bảo mật y hệt Wi-Fi: Mac gửi `usbHello{khoá host}` chỉ để viewer chọn khoá IK; sau đó là IK/Noise, quyền theo thiết bị, thu hồi cắt phiên. **Chưa ghép đôi với Mac này qua Wi-Fi/QR thì USB bị từ chối** (`pairingRequired`); không có đường tắt cho plaintext.
- Media chỉ qua MediaOverTcp (kind 0x04, mã hoá bằng khoá TCP). Audio luôn AAC-ELD.
- Giới hạn v1: xoay màn hình iPhone giữa phiên không tự đổi cấu hình (Mac nối lại); app vào nền thì phiên đóng; chưa có tên máy (usbmux không cho tên).

### Android qua cáp (`adb reverse`) — chỉ tài liệu, chưa tự động hoá

`adb reverse tcp:47800 tcp:47800` rồi nhập `127.0.0.1:47800` trong app Android (nhập tay). **Cảnh báo:** `adb reverse` chỉ chuyển TCP. Viewer Android hiện chưa có MediaOverTcp, còn video/audio/input đi UDP tới `127.0.0.1:<udpPort>` của chính điện thoại → không tới Mac. Vì vậy qua cáp hiện chỉ kênh control (bắt tay, ghép đôi) thông; muốn có hình phải bổ sung MediaOverTcp cho Android (cờ `mediaOverTcp` ở viewer + host chấp nhận cho peer loopback) — chưa làm.

## 3. Cờ kiểm thử (build Debug, `apple/mac-app/Sources/App/AutomationHooks+Audio.swift`)

`--auto-approve-audio`, `--audio-report`, `--audio-narrow` (ép AAC-ELD), `--audio-mute-local`, `--usb-loopback` (giả lập cáp bằng TCP loopback; cần ghép đôi trước bằng `--print-pair-uri --pair-token self --disconnect-after N`), `--usb-probe`. Luôn đặt `CFFIXED_USER_HOME` trỏ thư mục tạm khi chạy các cờ này để không ghi vào `paired-devices.json` thật.

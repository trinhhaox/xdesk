# Xdesk Wire v1 — Message điều khiển (JSON)

Payload của frame `kind 0x02` là một JSON object **phẳng**: `{"t":"<type>","id":<u32>, ...trường riêng}`.
`id` ghép yêu cầu/phản hồi (phản hồi dùng lại `id` của yêu cầu). Bộ giải mã bỏ qua trường lạ; `t` lạ được báo
là "unknown" và bỏ qua (tương thích tiến). JSON hỏng / thiếu trường / sai kiểu → `malformedJSON`; sai giới hạn giá trị → `invalidField`.

| `t` | Hướng | Trường | Giới hạn |
|---|---|---|---|
| `hello` | V→H | `ver` string "1.0", `caps` u32, `name` string | |
| `welcome` | H→V | `ver`, `sessionId` string, `caps` (giao) u32 | |
| `reject` | cả hai | `reason` string ("version"…), `detail` string? | |
| `display.config` | V→H | `w`,`h` u32, `scale` number, `fps` u32, `codec` "h264"\|"hevc", `mode` "extend"\|"mirror"? (vắng = extend; mirror = màn hình Mac phản chiếu màn hình ảo theo kích thước viewer), `mirrorFit` "native"\|"fitDevice"\|"touch"? (chỉ có nghĩa khi `mode` = mirror; vắng = fitDevice; xem "Bản sao: ba kiểu vừa khung"), `videoPaused` bool? (vắng = false; true = vào thẳng chế độ Chỉ điều khiển, host chưa phát hình; xem `video.pause`), `displayId` u32? (vắng = màn hình mặc định; chọn màn hình vật lý khi Mac có ≥ 2 màn hình, cần cap `multiDisplay`; id lấy từ `display.list`) | w,h 1…16384; fps 1…240; scale (0,8] |
| `display.ready` | H→V | `udpPort` u16, `streamId` u16 | udpPort ≠ 0 (đường hầm USB: giữ chỗ = 1, bỏ qua vì media đi qua TCP, xem `framing.md`) |
| `keyframe.request` | V→H | `streamId` u16 | |
| `net.report` | V→H | `rttMs`,`lossPermille`,`jitterMs`,`recvKbps` u32 | lossPermille ≤ 1000 |
| `bitrate.set` | H↔V | `kbps` u32 | |
| `clip.offer` | cả hai | `kind` "text"\|"image", `size` u32, `hash` string? (SHA-256 hex thường, 64 ký tự) | size 1…10 485 760 (10 MiB); vắng `hash` = bên cũ, bên nhận vẫn pull nhưng không chống lặp theo hash |
| `clip.pull` | cả hai | `kind` "text"\|"image" | chỉ trả lời khi còn mục `kind` đã offer |
| `clip.data` | cả hai | `kind`, `size` u32, `hash` string (SHA-256 hex) | trả lời `clip.pull`; size 1…10 MiB; ngay sau là bulk frames (xem "Clipboard") |
| `control.state` | cả hai | `owner` "agent"\|"human" | |
| `ping` | V→H | `t0` i64 (ms) | |
| `pong` | H→V | `t0` (lặp lại), `t1` (host nhận), `t2` (host gửi) i64 | |
| `bye` | cả hai | `reason` string? | |
| `input.text` | V→H | `text` string (Unicode, IME/Telex) | ≤ 4096 byte UTF-8 |
| `pair.result` | H→V | `accepted` bool | gửi một lần sau message 3 của XX/XXpsk3, trước mọi thứ khác (`crypto-handshake.md` §4) |
| `agent.approve` | cả hai | yêu cầu H→V: `requestId` string (≤ 64 B), `agentName` string (≤ 128 B), `summary` string (≤ 512 B), `expiresAt` i64 (ms Unix, giờ host); trả lời V→H: `requestId`, `allow` bool | Host xin viewer duyệt quyền điều khiển cho agent AI (phase 08); bản yêu cầu không có `allow`. Host chỉ nhận trả lời từ viewer có quyền `input`, khớp `requestId` đang chờ; trả lời đầu tiên (Mac hoặc điện thoại) thắng, trả lời muộn bị bỏ. Viewer cũ bỏ qua type lạ (mục "Thêm trường tuỳ chọn…") nên yêu cầu hết hạn ở host |
| `display.reconfigure` | V→H | cùng trường và giới hạn với `display.config` | cap `hotReconfigure` (bit 7). Đổi cấu hình giữa phiên mà không đóng kết nối (xoay máy, đổi kiểu vừa khung, đổi màn hình, đổi codec): host dừng pipeline cũ, dựng lại theo cấu hình mới rồi trả `display.ready` **dùng lại `id` của yêu cầu** (`udpPort` giữ nguyên, `streamId` giữ nguyên); sau đó gửi lại `display.list` nếu có `multiDisplay`. Giới hạn giá trị y hệt `display.config` (sai → `invalidField`) |
| `display.list` | H→V | `displays` mảng `{id u32, name string, width u32, height u32, isMain bool}` | cap `multiDisplay` (bit 12). Danh sách màn hình **vật lý** của Mac; host gửi sau `display.ready` (cả lần đầu lẫn sau `display.reconfigure`), **không gửi khi danh sách rỗng**. `id` là giá trị dùng cho `display.config.displayId`. Thiếu trường nào trong phần tử → `malformedJSON` |
| `video.pause` | V→H | `streamId` u16 | cap `videoPause` (bit 8). Viewer sang chế độ Chỉ điều khiển: host tạm dừng capture/encode video; kênh input và âm thanh vẫn chạy. Khi viewer vào phiên đã ở chế độ này (`display.config.videoPaused`), host vẫn gửi một gói probe rỗng để viewer biết kênh UDP thông |
| `video.resume` | V→H | `streamId` u16 | cap `videoPause`. Tiếp tục phát; host bắt đầu lại bằng keyframe. Pause/resume lặp lại trạng thái hiện tại thì bỏ qua |
| `system.lock` | V→H | (không có trường riêng) | Khoá màn hình Mac (tắt màn hình, `pmset displaysleepnow`). Không có cap riêng; host chỉ làm khi viewer có quyền `input`, nếu không bỏ im lặng; không có phản hồi |
| `system.lock.result` | H→V | `ok` bool, `message` string (tiếng Việt) | Không cần cap (viewer cũ bỏ qua type lạ). Host trả lời `system.lock`: `ok:true` "Đã khoá Mac"; chỉ tắt được màn hình (⌃⌘Q không khoá được) → `ok:false` "Mac chỉ tắt màn hình — bật 'Yêu cầu mật khẩu' trong Cài đặt Mac"; thiết bị thiếu quyền `input` → `ok:false`. Thiếu `message` → `malformedJSON` |
| `host.state` | H→V | `videoAvailable` bool, `locked` bool | Không cần cap (viewer cũ bỏ qua type lạ). Mac đang khoá/tắt màn hình nên host chưa capture được: phiên **không** bị đóng, `display.ready` vẫn trả bình thường, kênh control/UDP probe/input/`system.lock`/`system.unlock`/clipboard vẫn chạy, chỉ không có khung hình. Host gửi `videoAvailable:false` ngay sau handshake (nếu vậy) và `videoAvailable:true` + keyframe khi màn hình sáng/mở khoá và capture chạy lại. Viewer không coi việc thiếu khung hình là mất liên lạc khi `videoAvailable:false` và nên hiện lớp phủ "Mac đang khoá" kèm nút mở khoá. Thiếu `locked` → `malformedJSON` |
| `system.unlock` | V→H | `token` string?, `sig` string? (base64 DER ECDSA) | cap `remoteUnlock` (bit 10). Đánh thức/mở khoá Mac, host luôn trả `system.unlock.result` hoặc `system.unlock.challenge`. `token` hiện host bỏ qua. **Không có `sig` = xin thử thách; có `sig` = trả lời thử thách** (xem "Mở khoá có chứng thực sinh trắc học"). `sig` không phải base64 hoặc dài ngoài 8…80 byte → `invalidField`. **Giới hạn tần suất 3 lần/60 s mỗi phiên, tính riêng cho yêu cầu thử thách và cho lần gửi `sig`**: lần thứ 4 trong cửa sổ trả `ok:false` ("Thử mở khoá quá nhiều lần, vui lòng đợi 1 phút") và không thực hiện. Mở khoá bằng mật khẩu chỉ khi Mac bật mở khoá từ xa **và** thiết bị có quyền `unlock` **và** chứng thực hợp lệ; thiếu chính sách mà thiết bị có quyền `input` và màn hình đang không khoá → chỉ đánh thức màn hình, `ok:true`; còn lại `ok:false` ("Mac chưa bật mở khoá từ xa cho thiết bị này") |
| `system.unlock.challenge` | H→V | `nonce` string (base64, đúng 32 byte), `ttlMs` u32 (30000) | cap `unlockAttestation` (bit 13). Trả lời `system.unlock` không có `sig`. `nonce` dùng một lần, hết hạn sau `ttlMs`; nonce sai độ dài → `invalidField` |
| `unlock.key` | V→H | `alg` "p256-ecdsa-sha256", `pub` string (base64 X9.63 uncompressed, 65 byte, byte đầu 0x04) | cap `unlockAttestation` (bit 13). Viewer gửi một lần ngay sau khi phiên bắt đầu stream; host không phản hồi. `alg` lạ hoặc `pub` sai độ dài/định dạng → `invalidField` |
| `window.pick` | V→H | `x`, `y` số thực (điểm) | cap `windowControl` (bit 14). Toạ độ theo hệ điểm của luồng video đang xem = kích thước khung hình giải mã (px) / `display.config.scale` (với màn hình ảo = `w/scale` × `h/scale`; với Bản sao `native` là kích thước encode của màn hình Mac / `scale`) Host chọn cửa sổ trên cùng tại điểm (bỏ qua cửa sổ Xdesk, Dock, menu bar, desktop) và trả `window.selected`. `x`/`y` không hữu hạn → `invalidField` |
| `window.selected` | H→V | `ok` bool; `windowId` u32?, `app` string?, `title` string?, `frame` {`x`,`y`,`w`,`h`}?, `resizable` bool?, `message` string? | cap `windowControl`. Trả lời `window.pick` và mọi `window.adjust` (frame mới, theo hệ toạ độ viewer). `ok:false` kèm `message` tiếng Việt ("Không có cửa sổ ở đây"). `windowId` do host cấp, chỉ có hiệu lực trong phiên. `frame` có `w`/`h` ≤ 0 hoặc không hữu hạn, hoặc `app`/`title`/`message` > 256 B → `invalidField` |
| `window.adjust` | V→H | `windowId` u32, `op` "move"\|"resize"\|"preset"; `dx`,`dy` (move); `w`,`h` (resize); `preset` "fill"\|"left"\|"right"\|"center"\|"restore" (preset) | cap `windowControl`. `move` cộng dồn `dx`,`dy` (điểm) vào frame hiện tại; `resize` đặt kích thước tuyệt đối (giữ tâm, hoặc góc trên-trái nếu tâm làm tràn màn); `preset`: fill = vùng hiển thị trừ menu bar/Dock, left/right = nửa màn, center = 70% màn đặt giữa, restore = frame trước lần chỉnh đầu tiên trong phiên. Host kẹp trong màn đang chiếu, tối thiểu 200×150. Tối đa 60 lần/giây (host gộp, áp frame mới nhất mỗi ~16 ms). Thiếu trường của `op` / `w`,`h` ≤ 0 / số không hữu hạn → `invalidField`; `op`/`preset` lạ → `malformedJSON`. Host luôn trả `window.selected` |
| `system.unlock.result` | H→V | `ok` bool, `message` string (tiếng Việt, hiển thị cho người dùng) | trả lời `system.unlock`; thiếu `message` → `malformedJSON` |
| `media.key` | V→H | `key` "playPause"\|"next"\|"previous"\|"volumeUp"\|"volumeDown"\|"mute" | cap `mediaKeys` (bit 11). Host chèn phím media/âm lượng hệ thống, chỉ khi viewer có quyền `input` và app đã có quyền Accessibility; không phản hồi. Giá trị `key` lạ → `malformedJSON` |
| `file.start` | cả hai | `transferId` string (1…64 B UTF-8), `name` string (1…255 B), `size` u64 | cap `fileTransfer` (bit 9). Mở một lần truyền tệp streaming. `size` ≤ 2 GiB = 2 147 483 648 (vượt → `invalidField`). Khoá là `transferId` (không phải `id`, vốn là `id` envelope). Xem "Truyền tệp" |
| `file.chunk` | cả hai | `transferId`, `size` u32 | `size` 1…65 536. **Ngay sau** message này là đúng một frame `bulk` (kind 0x03) dài đúng `size` byte |
| `file.done` | cả hai | `transferId`, `hash` string (SHA-256 hex thường 64 ký tự của toàn bộ tệp) | kết thúc lần truyền; bên nhận kiểm đủ byte và hash |
| `file.cancel` | cả hai | `transferId`, `reason` string? | huỷ lần truyền đang chạy (bên nào cũng gửi được); bên nhận xoá tệp tạm |
| `file.offer` | V→H | `name` string, `size` u32, `hash` string (có thể rỗng) | **Cũ (legacy)**: chỉ host còn nhận để tương thích viewer cũ; viết mới dùng `file.start`. Mở tệp nhận theo `name`. Không kiểm giới hạn size/hash |
| `file.data` | V→H | `name` string, `chunk` string (Base64), `isLast` bool | **Cũ (legacy)**: nối `chunk` vào tệp đã `file.offer` cùng `name`; `isLast` = true thì đóng tệp. Không có kiểm SHA-256 |
| `agent.help` | cả hai | yêu cầu H→V: `requestId` string, `reason` string; trả lời V→H: `requestId`, `resolved` true | Agent AI cần người dùng tự xử lý (captcha, OTP, đăng nhập). Bản yêu cầu không có `resolved`; viewer hiện `reason` và khi người dùng xong thì trả `{requestId, resolved:true}`. Host chỉ nhận trả lời từ viewer có quyền `input`. Không có cap riêng; viewer cũ bỏ qua như type lạ. Cùng khuôn với `agent.approve` |
| `rekey` | cả hai | (không có trường riêng) | chỉ trên kênh mã hoá; frame cuối dưới khoá TCP cũ, bên nhận đổi khoá nhận rồi bỏ message (`crypto-handshake.md` §7). `id` = 0 |
| `rekey.resync` | cả hai | `epoch` u32, `ask` bool | `ask:false` = "epoch gửi UDP của tôi là `epoch`" → bên nhận kéo khoá nhận lên epoch đó (≤ 64 epoch); `ask:true` = "hãy báo epoch gửi của bạn" (`epoch` = epoch nhận hiện tại của người hỏi) (`crypto-handshake.md` §8) |

Đồng bộ đồng hồ kiểu NTP 4 mốc: viewer ghi `t3` lúc nhận pong; `offset = ((t1-t0)+(t2-t3))/2`, `rtt = (t3-t0)-(t2-t1)`.

Thêm trường tuỳ chọn ở minor mới là tương thích; trường `detail`/`reason` vắng mặt = `null` hoặc không có khoá.

## Ví dụ (dạng chuẩn của test vectors: khoá sắp xếp, không khoảng trắng)

```
{"caps":67,"id":1,"name":"Mac của Hào","t":"hello","ver":"1.0"}
{"caps":3,"id":1,"sessionId":"s-7f3a","t":"welcome","ver":"1.0"}
{"detail":"major 2 not supported","id":2,"reason":"version","t":"reject"}
{"codec":"h264","fps":60,"h":1440,"id":3,"scale":2,"t":"display.config","w":2560}
{"codec":"h264","fps":60,"h":1440,"id":3,"mirrorFit":"native","mode":"mirror","scale":2,"t":"display.config","w":2560}
{"id":10,"t":"ping","t0":1700000000123}
```
Số thực `scale` có thể viết `2` hoặc `2.0`; bộ giải mã chấp nhận cả hai. Bộ mã hoá Swift sắp xếp khoá theo thứ tự
byte và không escape dấu `/`. Danh sách đầy đủ + frame hex: `protocol/test-vectors/control-frames.json`.

## Bản sao: ba kiểu vừa khung (`mirrorFit`)

Chỉ áp dụng khi `display.config.mode` = `mirror`. Host/viewer cũ bỏ qua khoá lạ nên vẫn chạy như `fitDevice`; giá trị lạ là `malformedJSON`.

| `mirrorFit` | Host làm gì | `w`,`h`,`scale` |
|---|---|---|
| `native` | Không đổi/mirror màn hình Mac. Capture màn hình chính ở độ phân giải thật, cạnh dài tối đa 2560 px (giữ tỉ lệ, làm tròn xuống số chẵn). Viewer tự letterbox + zoom/pan; xoay viewer không đổi gì ở Mac | Chỉ là gợi ý, host bỏ qua. Viewer luôn gửi (cạnh dài, cạnh ngắn) theo điểm × scale để xoay máy không sinh `display.config` mới |
| `fitDevice` (mặc định) | Màn hình ảo đúng `w`×`h` px, mọi màn hình thật phản chiếu nó (desktop Mac theo kích thước/tỉ lệ viewer, theo chiều xoay). HiDPI khi `scale` ≥ 2 | Kích thước viewer theo điểm ảnh gốc |
| `touch` | Như `fitDevice` nhưng luôn HiDPI và độ phân giải logic thấp để điều khiển macOS cỡ 22–24 pt đủ to cho ngón tay | Viewer tính: `w`,`h` = 2 × kích thước logic, `scale` = 2 |

**Công thức `touch`** (viewer tính; điểm = điểm của viewer, xấp xỉ kích thước vật lý vì mọi iPhone ~ 163 ppi theo điểm):

```
short, long   = min/max(pointsWidth, pointsHeight)
magnification = clamp( min(44/22, short/540, long/640) )     // ≥ 44 pt cho điều khiển 22 pt, nhưng cạnh ngắn logic không nhỏ hơn 540
logical       = round(points / magnification)                      // theo từng cạnh, giữ chiều xoay
w, h          = 2 × logical.width, 2 × logical.height ; scale = 2   // mode HiDPI: macOS thấy logical, backing 2×
```

Sàn 540 pt cạnh ngắn là giới hạn đo thực của macOS (mode HiDPI cạnh ngắn logic ≤ 520 bị `CGDisplaySetDisplayMode` từ chối, 540 được), nên trên iPhone điều khiển 22 pt chỉ lên ~16 pt (`fitDevice` khi scale 3: logic 590×1278 → ~14,7 pt, nên ở iPhone `touch` chỉ nhỉnh hơn ~9%, rõ hơn ở màn hình lớn). iPad (820×1180 pt) lên ~33 pt. Host cưỡng chế HiDPI cho `touch` và danh sách mode của màn hình ảo chính là mode logic đó (`w/2`×`h/2`).

## Âm thanh (cap 0x04 PCM, 0x08 AAC-ELD, phase 09a)

Host chỉ đưa `audioPCM`/`audioAACELD` vào `welcome` khi thiết bị viewer đã được cấp quyền `audio` (mặc định tắt) — giống clipboard: quyền tắt giữa phiên thì host ngừng gửi trong ≤ 1 s. Không có message điều khiển riêng; gói audio ptype 0x20 và việc chọn codec: xem `media-packets.md`.

## Clipboard (cap 0x10, phase 09b)

- Chỉ dùng khi cả hai bên có bit `clipboard` trong `caps` chung. Host chỉ đưa bit này vào `welcome` khi thiết bị viewer đã được cấp quyền
  clipboard (mặc định tắt) → quyền tắt thì không bên nào gửi/nhận; host còn kiểm lại quyền mỗi message nên tắt giữa phiên có hiệu lực ngay (viewer thấy từ phiên sau).
- Luồng: A thấy clipboard đổi → `clip.offer{kind,size,hash}` → B (muốn nhận) `clip.pull{kind}` → A gửi `clip.data{kind,size,hash}`
  rồi `ceil(size/65536)` frame **bulk** (kind 0x03, mỗi frame ≤ 65 536 B plaintext, kênh mã hoá như control) liền nhau; B ghép đủ `size` byte, kiểm SHA-256 = `hash`.
  A mã hoá và ghi toàn bộ message + bulk trong một lượt nên không message nào chen giữa các chunk (nhưng `rekey` có thể chen và là nội bộ).
- Nội dung: `text` = UTF-8 hợp lệ; `image` = PNG (8 byte chữ ký `89 50 4E 47 0D 0A 1A 0A`). Cả hai ≤ 10 MiB. Sai chữ ký/UTF-8/hash/size → bỏ cả lần truyền, không ghi clipboard.
  Bulk không có `clip.data` trước hoặc thừa byte → bỏ.
- Không bao giờ offer mục có type `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` (1Password, Bitwarden…).
- Chống lặp: bên nhận ghi nhớ `changeCount` sau khi ghi và hash vừa ghi (3 s) nên không offer ngược; clipboard có sẵn lúc bắt đầu phiên không được gửi.
- Mac thăm dò `NSPasteboard.changeCount` mỗi 500 ms; iOS chỉ đọc `UIPasteboard` khi người dùng bấm "Gửi clipboard sang Mac" (tránh banner "đã dán từ").

## Truyền tệp (cap 0x200 `fileTransfer`)

Hai chiều qua kênh control mã hoá (Mac nhận tệp viewer gửi; Mac gửi tệp sang viewer). Không có luồng riêng: tệp đi bằng cặp `file.chunk` + frame `bulk`.

- Luồng: A gửi `file.start{transferId,name,size}` → lặp `file.chunk{transferId,size}` + **một** frame `bulk` đúng `size` byte (mỗi mảnh ≤ **64 KiB** = 65 536 B; mảnh cuối có thể ngắn hơn) → `file.done{transferId,hash}`. Người gửi ghi cặp `file.chunk` + `bulk` trong **một lượt** nên không message nào chen giữa hai message đó, nhưng `ping`, `file.cancel`, `rekey` vẫn chen được giữa các mảnh. Nhiều `transferId` có thể đang chạy; `file.chunk` cho `transferId` chưa mở thì bỏ cả frame bulk theo sau.
- Giới hạn: tệp ≤ **2 GiB** (`size`), `transferId` ≤ 64 B, `name` ≤ 255 B, mỗi mảnh 1…65 536 B. Tệp 0 byte hợp lệ (không có `file.chunk`).
- Toàn vẹn: `hash` = SHA-256 (hex thường) của **toàn bộ nội dung tệp** (cộng dồn qua các mảnh). Bên nhận chỉ giữ tệp khi `file.done` đến với tổng byte nhận = `size` và hash khớp; sai → xoá tệp tạm, báo lỗi "sai SHA-256". Mảnh sai kích thước so với `file.chunk`, hoặc làm vượt `size` → bỏ cả lần truyền.
- Tên tệp: không bao giờ là đường dẫn. Bên nhận chỉ lấy thành phần cuối (tách theo `/` và `\`), tên rỗng/`.`/`..` thành `file`; ghi vào tệp tạm `.xdesk-<uuid>.part` rồi đổi tên khi xong; trùng tên thì thêm hậu tố `name (1).ext`, `name (2).ext`… (không ghi đè). Mac lưu tệp nhận vào `~/Downloads/Xdesk/`.
- Quyền: host kiểm quyền của thiết bị viewer trước khi nhận/gửi tệp; thiếu quyền thì bỏ message im lặng (tên quyền: xem `docs/project-changelog.md`, mục Unreleased).
- Tương thích: viewer cũ chưa có bit `fileTransfer` chỉ dùng được `file.offer`/`file.data` (Base64, V→H, không kiểm hash); bộ cài đặt mới nên dùng `file.start`/`file.chunk`/`file.done`.

## Khoá và mở khoá từ xa (cap 0x400 `remoteUnlock`)

`system.lock` không cần cap riêng, còn `system.unlock` chỉ gửi khi cap `remoteUnlock` nằm trong giao. Host chỉ đưa bit này vào `welcome` khi thiết bị viewer được cấp quyền mở khoá và Mac đã bật mở khoá từ xa (đã lưu mật khẩu đăng nhập trong Keychain). Mật khẩu **không bao giờ** đi qua wire. Giới hạn 3 lần/60 s tính theo phiên (xem hàng `system.unlock`).

## Luồng

1. `hello` → `welcome` (hoặc `reject`). 2. `display.config` → `display.ready`. 3. Media UDP chạy; viewer gửi `net.report`
định kỳ, `keyframe.request` khi mất keyframe. `bye` đóng phiên.

## Mở khoá có chứng thực sinh trắc học (cap 0x2000 `unlockAttestation`)

Mục tiêu: lệnh mở khoá phải đi kèm bằng chứng mật mã rằng điện thoại vừa qua xác thực sinh trắc học/mã khoá, để client bị sửa chỉ có khoá ghép đôi không vượt được bước này. Host đưa bit 13 vào `welcome` mỗi khi đưa bit 10 (`remoteUnlock`); viewer chỉ đưa bit 13 khi có khoá ký.

**Khoá điện thoại.** P-256, chỉ ký được sau khi người dùng hiện diện: iOS dùng khoá Secure Enclave (`privateKeyUsage` + `userPresence`, ThisDeviceOnly); Android dùng AndroidKeyStore (`setUserAuthenticationRequired`, mỗi lần ký xác thực qua `BiometricPrompt` + `CryptoObject`, BIOMETRIC_STRONG hoặc DEVICE_CREDENTIAL). Chữ ký ECDSA-SHA256 dạng DER (X9.62); khoá công khai X9.63 uncompressed (65 byte). Dữ liệu được ký: `"xdesk v1 unlock"` (UTF-8, 15 byte) `||` `hostStaticPub` (32 byte) `||` `viewerStaticPub` (32 byte) `||` `nonce` (32 byte), với hai khoá tĩnh Noise X25519 của chính phiên này (cả hai đầu đều biết), nên chữ ký không dùng lại được ở cặp host/viewer khác. Quyết định sản phẩm: khoá yêu cầu "người dùng hiện diện", **cho phép mật mã/khoá màn hình** (iOS `userPresence`, Android `DEVICE_CREDENTIAL`), không chỉ sinh trắc học; ai biết mật mã điện thoại và cầm điện thoại đã mở khoá phiên thì mở khoá được Mac.

**Luồng.** (1) `system.unlock` không `sig` → host kiểm tra giới hạn tần suất, chính sách Mac/thiết bị, viewer có cap và đã có khoá → trả `system.unlock.challenge`. (2) Viewer chỉ ký khi người dùng vừa bấm "Mở khoá Mac" (cờ hiệu lực 30 s và đúng một thử thách; thử thách không mời bị bỏ), lời nhắc xác thực nêu tên Mac; ký xong gửi `system.unlock{sig}`. Mỗi lần bấm, viewer gửi lại `unlock.key` trước khi xin thử thách. (3) Host xác minh chữ ký bằng khoá đã đăng ký của thiết bị, **tiêu thụ nonce ở mọi lần thử** (đúng hay sai), rồi mới chạy mở khoá. Nonce lưu theo phiên, mỗi lần phát nonce mới thay nonce cũ. Mọi lỗi → `system.unlock.result{ok:false}` kèm thông báo tiếng Việt.

**Đăng ký khoá (TOFU, fail-closed).** Host lưu khoá trong bản ghi thiết bị đã ghép (`unlockKey`, base64url, nằm trong vùng HMAC; chỉ ghi khi có). Chỉ nhận `unlock.key` khi thiết bị đang có quyền `unlock`, chưa có khoá **và trong 5 phút sau thao tác của người dùng trên Mac** (bật quyền "Mở khoá Mac" cho thiết bị hoặc bấm "Đặt lại khoá"; cửa sổ chỉ nằm trong bộ nhớ, dùng một lần). Thiết bị đã bật quyền từ trước phải bấm "Đặt lại khoá" một lần. Mac và điện thoại đều hiện dấu vân tay khoá (8 byte đầu SHA-256, `XXXX-XXXX-XXXX-XXXX`) để đối chiếu. Giới hạn tần suất (3 lần/60 s cho thử thách, 3 cho chữ ký, 10 cho `unlock.key`) tính theo khoá tĩnh của thiết bị, không theo phiên, nên kết nối lại không làm mới hạn mức. Thông báo khoá lạ chỉ hiện một lần mỗi thiết bị mỗi phiên. Khoá khác khoá đã lưu **không** ghi đè: host giữ khoá cũ, ghi log, báo trên Mac; mở khoá sau đó thất bại tới khi người dùng bấm "Đặt lại khoá" hoặc tắt quyền "Mở khoá Mac" (cả hai xoá khoá; `unlock.key` kế tiếp đăng ký lại).

**Viewer cũ.** Phiên không có cap bit 13, hoặc thiết bị chưa có khoá: `system.unlock` **không** bao giờ gõ mật khẩu; host chỉ đánh thức màn hình và trả `ok:false` ("Cập nhật app Xdesk trên điện thoại để mở khoá bằng Face ID"). Vector chữ ký dùng chung nằm ở khoá `unlockAttestation` của `protocol/test-vectors/control-frames.json` (khoá riêng = scalar 0x01…0x20, nonce = 0x00…0x1f).

**Lưu trữ và hạ cấp.** Khi có ít nhất một thiết bị mang `unlockKey`, `paired-devices.json` ghi `schemaVersion` 2 (không có khoá thì vẫn 1). Bản cũ chỉ hiểu 1 sẽ ném `unsupportedSchema` và giữ nguyên file thay vì ghi lại bản ghi thiếu khoá (sẽ sai HMAC và bị cách ly). **Hạ cấp xuống bản trước tính năng này không được hỗ trợ.**

Phần khoá màn hình macOS chỉ tính là "đã khoá" khi phiên đang ở console (`kCGSessionOnConsoleKey`), để chuyển người dùng nhanh không làm mật khẩu rơi vào phiên khác. Dữ liệu vector chung có thêm `hostKey` (0x11 × 32) và `viewerKey` (0x22 × 32).

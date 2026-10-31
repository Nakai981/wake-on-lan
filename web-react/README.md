# Wake My PC — React + Vite PWA

Bản web độc lập, chuyển chức năng app Flutter sang React. Không dùng Flutter Web, SSR
hay Flutter SDK. Mã Flutter gốc giữ nguyên.

## Chạy nhanh

Cần Node.js 22.12+. Mở terminal trong `web-react/`:

```sh
npm ci
npm run build
npm start
```

Mở **http://localhost:8787**. Nếu PowerShell chặn `npm.ps1`, dùng `npm.cmd`.
Server vừa phục vụ file tĩnh trong `dist/`, vừa làm LAN bridge.

**Server yếu:** build trên máy phát triển rồi chép `dist/`, thư mục `server/`,
`package.json`, `package-lock.json` lên server; chạy `npm ci --omit=dev` và `npm start`.
Không cần build hay chạy Vite ở production. Asset Brotli/gzip được nén sẵn lúc build;
server chỉ stream file. React chạy trong trình duyệt. Flutter Web cũng chủ yếu chạy
ở client; React giảm bộ tải và chi phí phía trình duyệt, không phải loại bỏ một Flutter
runtime trên server. Cần đo RAM/CPU thực tế trên máy của bạn.

## Docker / Docker Compose

Từ thư mục `web-react/` trên **Docker Engine Linux trong cùng LAN với PC**:

```sh
cp .env.example .env
# Chỉnh .env: LAN_IP là IP LAN của server; PUBLIC_ORIGIN là URL dùng để mở web.
docker compose up -d
docker compose logs -f
```

Mặc định mở `http://localhost:8787` trên server. Để truy cập trực tiếp từ máy khác,
đặt `HOST=0.0.0.0`, `PUBLIC_ORIGIN=http://<IP-server>:8787`, `LAN_IP=<IP-server>`.
Để cài PWA/quét camera và ghép Agent trên điện thoại, cấu hình HTTPS reverse proxy như
hướng dẫn bên dưới, đặt `PUBLIC_ORIGIN` là URL HTTPS. Nếu đổi `PORT`, đổi cổng trong
`PUBLIC_ORIGIN` tương ứng khi dùng HTTP trực tiếp.

Compose hỗ trợ cả `build` và `image`. Chạy `docker compose up -d --build` để build mã nguồn
và gắn tên image theo `IMAGE` trong `.env`. Để chỉ dùng image có sẵn, chạy
`docker compose up -d --no-build --pull never`; hoặc chạy `docker compose pull` trước để lấy image
từ registry. Ví dụ `ghcr.io/your-account/wake-my-pc-web:latest` là tên mẫu,
không phải image được dự án publish sẵn. Để dùng image local mặc định, build riêng bằng
`docker build -t wake-my-pc-web:local .` hoặc `docker load` từ file tar.

Image build qua hai stage: Node/Vite build asset rồi runtime chỉ chạy Node và file tĩnh
đã nén. Dùng `network_mode: host` để bridge đọc đúng card mạng/ARP và gửi UDP broadcast;
không thêm `ports:`. Xem [tài liệu Docker về host networking](https://docs.docker.com/engine/network/drivers/host/).
Docker Desktop trên Windows/macOS không cung cấp tương đương đầy đủ
card mạng vật lý cho luồng này; nên chạy bridge bằng `npm start` trực tiếp trên Windows,
hoặc triển khai container trên server Linux trong LAN. Thiếu quyền ICMP của host thì
ping có thể không hoạt động, nhưng quét TCP vẫn hoạt động; không cần privileged mode.

Build riêng hoặc build trên máy mạnh rồi chuyển image sang server yếu:

```sh
docker build -t wake-my-pc-web:local .
docker save -o wake-my-pc-web.tar wake-my-pc-web:local
# Chép file tar và compose.yaml/.env sang server cùng kiến trúc CPU:
docker load -i wake-my-pc-web.tar
docker compose up -d --no-build
```

Healthcheck kiểm tra `/api/network` mỗi 30 giây. Dữ liệu thiết bị/mã ghép nối lưu tại
trình duyệt nên không cần Docker volume. Chạy `docker compose down` để dừng container.

## Luồng mạng

```text
React PWA → HTTPS/WebSocket cùng origin → Node.js LAN bridge luôn bật
                                             ├─ UDP Magic Packet → PC đang ngủ
                                             └─ TCP 47991 → Windows Agent
```

Trình duyệt không có socket UDP/TCP trực tiếp. Bridge cần nằm trong LAN chứa PC và chạy
trên NAS/router/Raspberry Pi hoặc máy khác luôn bật. Nếu bridge nằm trên chính PC cần
Wake, app mất kết nối khi PC Sleep/tắt. VPS bên ngoài không tự broadcast vào LAN nhà bạn.

Máy có nhiều card mạng/VPN: chọn IPv4 của card LAN, không phải IP của PC đích:

App ưu tiên card mạng vật lý thay cho Hyper-V/WSL/Docker/VPN. Card được chọn và dải quét
hiển thị trong wizard. Nếu có nhiều LAN vật lý, vẫn nên chọn rõ bằng `LAN_IP`.

```powershell
$env:LAN_IP = '192.168.1.10'
npm.cmd start
```

## Chức năng đã chuyển

| Tính năng Flutter | Bản React |
| --- | --- |
| Tiếng Việt, font Be Vietnam Pro, sáng/tối | Có, responsive điện thoại/desktop |
| Home theo một PC mặc định | Chọn/bỏ ngôi sao trong Danh sách |
| Trạng thái khi mở app | Mặc định Chưa bật, kể cả máy vừa thêm. Kiểm tra nền không ghi đè; có thể bật máy, đổi thủ công hoặc chọn Về tự động. |
| Nhiều PC, chỉnh sửa/xóa có xác nhận | LocalStorage theo origin |
| Thêm máy tính | Một popup: Quét LAN, Nhập thủ công hoặc Quét QR Windows Agent → Hoàn tất |
| Nhận IP/subnet/broadcast | Từ mạng **bridge**, không phải Wi-Fi điện thoại |
| Quét LAN, tiến độ và dừng | Tối đa 12 tác vụ song song, giới hạn /24, gồm máy bridge; dò TCP/ICMP |
| Tự lấy tên và MAC | Bridge đọc ARP/neighbor và reverse DNS khi chọn/nhập IP; có thể sửa hoặc nhập tay |
| Wake UDP, cấu hình broadcast/port/retry | Bridge gửi gói 102 byte thật |
| Console khi bấm Bật PC | Hiện đích UDP/MAC, kết quả từng lần gửi và HEX gói từ bridge, rồi mới báo đã gửi |
| Theo dõi Wake, dừng và xác nhận thủ công | Kiểm tra ngay sau gửi, lặp mỗi 3 giây. Phản hồi sớm → Đã bật ngay. Chưa phản hồi → Chờ khởi động 10–30 giây trước khi báo chưa có phản hồi. Có Bỏ qua — PC đã bật |
| Trạng thái foreground 15 giây | Kiểm tra lại khi quay về tab |
| Xác nhận thủ công PC đã bật | Nhãn riêng, giữ trong phiên đến phản hồi thật/lệnh nguồn |
| Chuyển trạng thái thủ công trên Home | Đã bật / Chưa bật, giữ qua các lần kiểm tra trong phiên; Về tự động để kiểm tra lại. Không gửi lệnh nguồn. Wake/Sleep/Shutdown trả về theo dõi trạng thái thật. |
| Đổi subnet, chẩn đoán, trợ giúp | Có |
| Lịch sử 60 hoạt động | Có |
| Ghép Agent bằng mã/QR camera | HMAC challenge/response tương thích Agent hiện có |
| Sleep/Shutdown, hủy trong 10 giây | Mỗi lệnh cần Quét QR Windows Agent hoặc Nhập mã thủ công và xác thực Agent mới, rồi xác nhận gửi. Giữ trạng thái hiển thị 20 giây trước khi kiểm tra lại; không tự gửi lại |
| Touchpad, nhấp trái/phải, kéo, cuộn, tốc độ | Hàng đợi giới hạn, gộp chuyển động, heartbeat/lease, nhả khi rời tab |
| Touch Bar, media/âm lượng, F1–F12, phím tắt | Gửi lệnh thật khi đã ghép Agent; có xem trước |
| Bàn phím tiếng Việt, Ctrl/Alt/Shift/Win | Tối đa 240 byte UTF-8/lần, không chứa ký tự điều khiển |
| Cài như ứng dụng, giao diện offline | Manifest và Workbox service worker |

Kiểm tra TCP không xác minh IP đó có cùng MAC; nên đặt DHCP reservation.
Tên/MAC chỉ tự điền khi bridge lấy được thông tin thật. Tên từ reverse DNS có thể không
có. MAC thuộc card tại IP đã chọn, không đảm bảo là card Ethernet nếu PC kết nối Wi-Fi;
hãy đối chiếu card hỗ trợ Wake-on-LAN. Bridge cần có lệnh `arp` (hoặc `ip neigh` trên Linux).
Quét tìm thiết bị qua TCP 47991/445/3389/22/80 (kể cả phản hồi từ chối kết nối), rồi thử
ping khi TCP im lặng. Cần lệnh `ping` trên máy bridge; thiếu lệnh hoặc thiếu quyền ICMP
thì vẫn quét TCP. Không tự mở firewall hay thay đổi quyền hệ thống. Thiết bị chặn cả TCP
và ICMP vẫn có thể không được tìm thấy; kết quả có thể gồm router/điện thoại.
Không phản hồi là **Chưa xác định**, không khẳng định PC tắt. Windows Agent phải build
từ mã nguồn mới nhất; xem `../windows-agent/README.md`. Nhập liệu chỉ áp dụng desktop đã
đăng nhập, không điều khiển UAC/màn hình đăng nhập hoặc app chạy quyền cao hơn Agent.

## HTTPS và điện thoại

Localhost cho phép thử PWA/Web Crypto. Trên điện thoại cần HTTPS với chứng chỉ thiết bị
tin cậy để cài PWA, dùng camera và mã hóa mã ghép nối. Reverse proxy website, `/api/*`
và WebSocket `/api/agent` trên cùng origin. Ví dụ Caddy cùng máy với bridge:

```caddyfile
wake.home.arpa {
    tls internal
    reverse_proxy 127.0.0.1:8787
}
```

Trỏ DNS tới máy bridge và cài/tin cậy CA nội bộ Caddy trên điện thoại; hoặc dùng domain
riêng với chứng chỉ HTTPS công khai hợp lệ. Cấu hình origin chính xác:

```powershell
$env:PUBLIC_ORIGIN = 'https://wake.home.arpa'
$env:LAN_IP = '192.168.1.10'
npm.cmd start
```

`PUBLIC_ORIGIN` không có `/` cuối. Proxy giữ Host và hỗ trợ WebSocket Upgrade.
Bridge mặc định bind `127.0.0.1`; nếu proxy chạy máy khác, cấu hình `HOST` và giới hạn
firewall cho proxy. Không mở bridge ra Internet. Không có tài khoản đăng nhập; thiết bị
trong LAN tin cậy có thể Wake qua giao diện, còn lệnh Agent cần mã ghép nối.
Bridge kiểm tra Host/Origin/subnet, không bật wildcard CORS.

Android Chrome: menu → Cài đặt ứng dụng. iPhone Safari: Chia sẻ → Thêm vào Màn hình chính.
Triển khai tại đường dẫn gốc `/`. QR scanner tải riêng khi mở camera, không dùng QR service.
Trong popup thêm máy, tab **Quét QR Agent** mở camera sau khi bấm nút. Trên Windows Agent,
chọn **Hiện QR ghép nối** và chọn card Ethernet. App điền IP/MAC, thử đọc tên máy; nếu không
có tên từ mạng, dùng tên gợi ý `PC <IP>` có thể sửa. **Hoàn tất** xác thực Agent qua HMAC
trước khi lưu thiết bị và mã ghép nối. Có thể dán nội dung QR nếu không dùng camera.

## Dữ liệu và offline

Danh sách/lịch sử lưu trong LocalStorage. Mã ghép nối mã hóa AES-GCM với khóa không xuất
được lưu trong IndexedDB; HMAC ký/xác minh tại trình duyệt. Bridge chỉ chuyển tiếp byte,
không nhận/lưu mã. Điều này không bảo vệ trước mã độc cùng origin hoặc người kiểm soát
thiết bị; chỉ ghép trên trình duyệt tin cậy. Dữ liệu Flutter không tự chuyển sang web.
Đổi domain/profile hoặc xóa site data sẽ mất dữ liệu/ghép nối ở origin cũ.

Sau lần tải đầy đủ và service worker kích hoạt, app mở giao diện/danh sách khi offline.
Wake/quét/điều khiển cần bridge online; lệnh không cache, không xếp hàng tự gửi lại.
Bản mới hiện nút cập nhật; tránh cập nhật khi đang giữ chuột/gửi lệnh.

## Phát triển và xác minh

Terminal 1:

```powershell
$env:DEV_ORIGIN = 'http://localhost:5173'
npm.cmd start
```

Terminal 2: `npm run dev`, mở `http://localhost:5173`. Vite proxy API/WebSocket tới bridge.
Chỉ dùng `DEV_ORIGIN` ở môi trường phát triển, bỏ biến này khi triển khai.

```sh
npm test
npm run build
```

Test: MAC/IP/subnet, QR/giới hạn lệnh, scan concurrency/hủy, UDP loopback, chặn
Origin/Host/đích ngoài LAN, chuyển tiếp WebSocket, HMAC và từ chối chữ ký giả.
Không gửi Sleep/Shutdown thật khi kiểm thử.

Chưa kiểm tra PC vật lý/cài PWA trên điện thoại thật. Cần thử Wake từ Sleep, ghép Agent,
chuột/phím, lệnh nguồn và hủy lệnh trên thiết bị của bạn. Kiểm tra trực quan bằng công cụ
trình duyệt chưa thực hiện được do công cụ không xác định chắc chắn URL Chrome trên Windows.

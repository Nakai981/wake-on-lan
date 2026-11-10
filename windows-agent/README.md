# Wake My PC — Windows Agent

Ứng dụng khay hệ thống cho Windows 10/11 (.NET Framework 4.8). Không cần .NET SDK trên máy chạy.

## Cài và ghép nối

1. Tải [WakeMyPcAgent.exe từ GitHub Releases](https://github.com/Nakai981/wake-on-lan/releases/latest/download/WakeMyPcAgent.exe) vào thư mục cố định, ví dụ `%LOCALAPPDATA%\WakeMyPcAgent\app`. Bản phát hành chỉ cần một EXE, không cần giải nén hay DLL bên cạnh.
2. Chạy `WakeMyPcAgent.exe`. Lưu đúng IP và MAC Ethernet hiển thị trong cửa sổ vào app điện thoại.
3. Khi Windows Firewall hỏi, chỉ cho phép Agent trên mạng **Private** tin cậy. Nếu không có thông báo, mở Windows Security → Firewall & network protection → Allow an app through firewall → thêm EXE và chọn Private. Người build từ mã nguồn cũng có thể dùng `Enable-Firewall.ps1` để giới hạn TCP 47991 theo chương trình, mạng Private và LocalSubnet. Không mở cổng router.
4. Trên điện thoại: menu PC → Ghép nối Windows Agent → nhập mã 32 ký tự từ Agent. Mã được lưu trong kho bảo mật của điện thoại.
5. Trên Home, chọn Sleep hoặc Tắt máy và xác nhận trên điện thoại. Windows không yêu cầu xác nhận thêm: Agent chờ theo cấu hình trong **Không gian của bạn → Thời gian chờ tắt / Sleep** rồi tự thực hiện (mặc định 10 giây, từ 1 giây đến 24 giờ). Cấu hình dùng chung cho cả hai nút và được lưu trên điện thoại cho các lần sau. Thông báo ở khay hệ thống hiển thị giờ dự kiến. Hủy từ điện thoại hoặc menu khay hệ thống nếu cần.
6. Tích **Chạy nền khi đăng nhập Windows** nếu muốn tự khởi động. Không cần quyền administrator. Đóng cửa sổ Agent chỉ thu xuống tray; chọn Thoát Agent để dừng. Các script startup bên dưới dành cho bộ mã nguồn, không cần tải cùng EXE.

## Bật / tắt khởi động cùng Windows

- `Enable-Startup.cmd`: tự chạy nền khi người dùng hiện tại đăng nhập Windows, đồng thời mở Agent ngay. Nếu Agent đang chạy thì không mở thêm hoặc hiện hộp thoại.
- `Disable-Startup.cmd`: bỏ tự chạy từ lần đăng nhập tiếp theo. Agent đang chạy vẫn hoạt động; muốn dừng ngay, chọn **Thoát Agent** ở khay hệ thống.
- Giữ nguyên vị trí thư mục sau khi bật. Nếu chuyển thư mục, chạy lại `Enable-Startup.cmd` tại vị trí mới.
- Hai file không thay đổi mã ghép nối hay firewall. Có thể bật/tắt bằng checkbox trong Agent; trạng thái được đọc lại khi mở lại Agent.
- Dùng PowerShell nếu cần: `powershell -ExecutionPolicy Bypass -File .\Enable-Startup.ps1 -NoStart` chỉ đăng ký tự chạy. Cả hai script hỗ trợ `-WhatIf` để xem trước mà không thay đổi cấu hình.

Đây là ứng dụng nền theo phiên người dùng, không phải Windows Service. Cần đăng nhập Windows để chạy tự động. Không cần Agent để gửi Wake-on-LAN bật máy.

Thời gian chờ tùy chỉnh cần build/cài lại Agent từ mã nguồn mới. Sau khi Agent xác nhận nhận lệnh, đóng app điện thoại vẫn tiếp tục đếm chờ trên PC. Agent phải tiếp tục chạy; thoát Agent hoặc khởi động lại Windows sẽ bỏ lệnh đang chờ. Đổi cấu hình trên điện thoại chỉ áp dụng từ lệnh tiếp theo.

## Bảo mật và phạm vi

### Touch Bar và bàn phím

Agent nhận văn bản Unicode (tiếng Việt), Esc/F1–F12, phím điều hướng, Ctrl/Alt/Shift/Win kết hợp, media và âm lượng. App đã ghép nối sẽ gửi thật qua màn Điều khiển; PC chưa ghép nối vẫn dùng xem trước. Chọn ô nhập trên PC trước khi gửi từ điện thoại. Mỗi lần gửi tối đa 240 byte UTF-8; app giữ nguyên nội dung để bạn tự sửa/xóa. Không tự gửi lại khi lỗi, tránh nhập trùng.

Phím tắt: Desktop = Win+D, đổi cửa sổ = Alt+Tab, chụp màn hình = Win+Shift+S, tìm kiếm = Win+S. Âm lượng dùng phím tăng/giảm của Windows, không đồng bộ phần trăm từ PC. Các thao tác dùng SendInput, chỉ áp dụng phiên desktop đã đăng nhập; không hỗ trợ UAC/màn hình đăng nhập hoặc ứng dụng có quyền cao hơn Agent. Tham khảo: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput

Mỗi tổ hợp có đủ nhấn và nhả trong cùng yêu cầu. Agent từ chối khi người dùng PC đang giữ phím bổ trợ. Lệnh được giới hạn danh sách cho phép và ký HMAC như lệnh nguồn; văn bản không được mã hóa trên đường truyền, chỉ dùng LAN tin cậy.

Touchpad trong mã nguồn hiện tại gửi chuyển động, nhấp trái/phải, kéo và cuộn thật qua Agent. Phiên kéo có heartbeat và thời hạn giữ chuột; Agent nhả chuột khi phiên hết hạn. Cần build/cài lại Agent từ mã nguồn hiện tại để dùng tính năng này.

Build lại Agent bằng `Build.ps1` và chạy app mới để dùng các tính năng điều khiển hiện tại. EXE đã tải không tự cập nhật. Bản phát hành [windows-agent-v1.0.0](https://github.com/Nakai981/wake-on-lan/releases/tag/windows-agent-v1.0.0) đã có nút **Hiện QR ghép nối** và thư viện QR nhúng trong EXE; không cần build lại chỉ để dùng QR.

### Ghép nối bằng QR

Trên Agent, bấm **Hiện QR ghép nối**, chọn card mạng có MAC giống PC đã lưu trên điện thoại. Trên app: menu PC → **Ghép nối Windows Agent** → **Quét QR từ Windows Agent**. Cấp quyền camera, quét mã rồi bấm **Ghép nối** để xác thực. App điền IP từ QR và chỉ cập nhật IP đã lưu sau khi ghép nối thành công. Nhập mã tay vẫn dùng được.

QR được tạo tại máy bằng QRCoder, chứa IP, MAC và mã ghép nối; không chia sẻ ảnh QR. Cửa sổ QR tự đóng sau 2 phút, nhưng mã vẫn hợp lệ cho đến khi bấm **Đổi mã**. Không có dịch vụ QR bên ngoài. `Build.ps1` nhúng QRCoder và giấy phép MIT vào EXE, nên bản phát hành chỉ tải một file.

### Quyền riêng tư

Agent không ghi màn hình, âm thanh, phím gõ hoặc lịch sử duyệt web; không có analytics, quảng cáo hoặc máy chủ thu thập dữ liệu. Agent nhận các lệnh đã xác thực từ thiết bị có mã ghép nối trong LAN Wi-Fi/Ethernet. Kiểm tra trạng thái phím bổ trợ chỉ để tránh can thiệp phím người dùng đang giữ khi thực hiện lệnh, không lưu lịch sử phím. Thông tin IP/MAC được dùng để kết nối và ghép nối; mã được lưu bằng DPAPI của Windows. Bạn có thể đổi mã, tắt tự khởi động và thoát Agent. Chỉ dùng trên LAN tin cậy, không chuyển tiếp cổng ra Internet. Tải bản phát hành từ GitHub cần Internet; điều khiển trong LAN không cần cloud. Wake qua Wi-Fi tùy phần cứng; ưu tiên Ethernet cho Wake-on-LAN.

Nếu build app điện thoại từ mã nguồn sau khi thêm plugin camera, cần build/cài lại app; hot reload không cài được plugin mới. Với Agent, dùng bản phát hành có QR ở trên hoặc build từ mã nguồn.

- Mã ngẫu nhiên 128 bit; không gửi mã qua mạng. Windows bảo vệ mã bằng DPAPI CurrentUser.
- TCP challenge/response HMAC-SHA256: challenge ngẫu nhiên riêng cho mỗi kết nối, client nonce và phản hồi ký. Mỗi kết nối nhận đúng một lệnh, giới hạn kích thước 512 byte, timeout 4 giây, tối đa 12 kết nối.
- Hỗ trợ `status`, `sleep`, `shutdown`, `cancel`, `power:<sleep|shutdown>:<seconds>` (1–86400 giây), `key:<mask>:<virtual-key>`, `text:<base64-utf8>` và các lệnh `mouse:<session>:<action>[:...]` có giới hạn. Hai lệnh `sleep`/`shutdown` cũ vẫn chờ 10 giây. Không có remote shell hay lệnh thực thi tùy ý.
- Giao thức xác thực nhưng không mã hóa nội dung lệnh; dùng trong LAN tin cậy. Không cung cấp truy cập Internet.
- Đổi mã từ Agent để thu hồi toàn bộ điện thoại cũ. Tắt máy không dùng `/f` nên ứng dụng chưa lưu có thể chặn.
- Sleep dùng SetSuspendState(false,false,false), giữ wake events; phụ thuộc phần cứng, chính sách Windows và quyền SeShutdownPrivilege. Lỗi được hiển thị trong Agent.
- Phản hồi `accepted` chỉ xác nhận đã lên lịch, không khẳng định PC đã tắt/sleep. PC có thể chặn hoặc hủy thao tác.

## Build

Từ mã nguồn: `powershell -ExecutionPolicy Bypass -File windows-agent\Build.ps1`.
Dùng trình biên dịch .NET Framework có sẵn trong Windows. Output: `dist/WakeMyPcAgent`.

## Gỡ

Bỏ chọn **Chạy nền khi đăng nhập Windows**, chọn **Thoát Agent** ở khay hệ thống, rồi xóa EXE hoặc thư mục riêng của app. Nếu cài từ bộ mã nguồn, có thể chạy `Disable-Startup.cmd` thay cho việc bỏ chọn checkbox. Có thể xóa rule được tạo bằng script firewall qua PowerShell admin: `Remove-NetFirewallRule -Name WakeMyPcAgent-Private`. Mã ghép nối lưu ở `%LOCALAPPDATA%\WakeMyPcAgent\pairing.bin`; xóa file này khi Agent đã thoát để tạo mã mới lần sau.

## Kiểm thử

`--test-server <port> <test-key-hex> <ready-file>` chỉ bind loopback, tự thoát sau 120 giây; trả `simulated` thay vì gọi API nguồn. Test mode không lưu mã, không bật startup, không gọi shutdown/Sleep. Không dùng mã ghép nối thật cho test.

API Microsoft: https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-setsuspendstate và https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown

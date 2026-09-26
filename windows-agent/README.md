# Wake My PC — Windows Agent

Ứng dụng khay hệ thống cho Windows 10/11 (.NET Framework 4.8). Không cần .NET SDK trên máy chạy.

## Cài và ghép nối

1. Giải nén `WakeMyPcAgent.zip` vào thư mục cố định, ví dụ `%LOCALAPPDATA%\WakeMyPcAgent\app`.
2. Chạy `WakeMyPcAgent.exe`. Lưu đúng IP và MAC Ethernet hiển thị trong cửa sổ vào app điện thoại.
3. Mở PowerShell **Run as administrator** tại thư mục đã giải nén, chạy `powershell -ExecutionPolicy Bypass -File .\Enable-Firewall.ps1`. Script chỉ mở TCP 47991 cho chương trình này, mạng Private và LocalSubnet. Không mở cổng router.
4. Trên điện thoại: menu PC → Ghép nối Windows Agent → nhập mã 32 ký tự từ Agent. Mã được lưu trong kho bảo mật của điện thoại.
5. Trên Home, chọn Sleep hoặc Tắt máy và xác nhận trên điện thoại. Windows không yêu cầu xác nhận thêm: Agent chờ 10 giây rồi tự thực hiện. Thông báo ở khay hệ thống chỉ để báo trạng thái. Hủy từ điện thoại hoặc menu khay hệ thống nếu cần.
6. Bấm đúp `Enable-Startup.cmd` để bật chạy cùng Windows và mở Agent chạy nền ngay. Không cần quyền administrator. Đóng cửa sổ Agent chỉ thu xuống tray; chọn Thoát Agent để dừng.

## Bật / tắt khởi động cùng Windows

- `Enable-Startup.cmd`: tự chạy nền khi người dùng hiện tại đăng nhập Windows, đồng thời mở Agent ngay. Nếu Agent đang chạy thì không mở thêm hoặc hiện hộp thoại.
- `Disable-Startup.cmd`: bỏ tự chạy từ lần đăng nhập tiếp theo. Agent đang chạy vẫn hoạt động; muốn dừng ngay, chọn **Thoát Agent** ở khay hệ thống.
- Giữ nguyên vị trí thư mục sau khi bật. Nếu chuyển thư mục, chạy lại `Enable-Startup.cmd` tại vị trí mới.
- Hai file không thay đổi mã ghép nối hay firewall. Có thể bật/tắt bằng checkbox trong Agent; trạng thái được đọc lại khi mở lại Agent.
- Dùng PowerShell nếu cần: `powershell -ExecutionPolicy Bypass -File .\Enable-Startup.ps1 -NoStart` chỉ đăng ký tự chạy. Cả hai script hỗ trợ `-WhatIf` để xem trước mà không thay đổi cấu hình.

Đây là ứng dụng nền theo phiên người dùng, không phải Windows Service. Cần đăng nhập Windows để chạy tự động. Không cần Agent để gửi Wake-on-LAN bật máy.

## Bảo mật và phạm vi

- Mã ngẫu nhiên 128 bit; không gửi mã qua mạng. Windows bảo vệ mã bằng DPAPI CurrentUser.
- TCP challenge/response HMAC-SHA256: challenge ngẫu nhiên riêng cho mỗi kết nối, client nonce và phản hồi ký. Mỗi kết nối nhận đúng một lệnh, giới hạn kích thước 512 byte, timeout 4 giây, tối đa 12 kết nối.
- Chỉ hỗ trợ `status`, `sleep`, `shutdown`, `cancel`. Không có remote shell hay lệnh tùy ý.
- Giao thức xác thực nhưng không mã hóa nội dung lệnh; dùng trong LAN tin cậy. Không cung cấp truy cập Internet.
- Đổi mã từ Agent để thu hồi toàn bộ điện thoại cũ. Tắt máy không dùng `/f` nên ứng dụng chưa lưu có thể chặn.
- Sleep dùng SetSuspendState(false,false,false), giữ wake events; phụ thuộc phần cứng, chính sách Windows và quyền SeShutdownPrivilege. Lỗi được hiển thị trong Agent.
- Phản hồi `accepted` chỉ xác nhận đã lên lịch, không khẳng định PC đã tắt/sleep. PC có thể chặn hoặc hủy thao tác.

## Build

Từ mã nguồn: `powershell -ExecutionPolicy Bypass -File windows-agent\Build.ps1`.
Dùng trình biên dịch .NET Framework có sẵn trong Windows. Output: `dist/WakeMyPcAgent`.

## Gỡ

Chạy `Disable-Startup.cmd`, chọn Thoát Agent, xóa thư mục app. Có thể xóa rule bằng PowerShell admin: `Remove-NetFirewallRule -Name WakeMyPcAgent-Private`. Mã ghép nối lưu ở `%LOCALAPPDATA%\WakeMyPcAgent\pairing.bin`; xóa file này khi Agent đã thoát để tạo mã mới lần sau.

## Kiểm thử

`--test-server <port> <test-key-hex> <ready-file>` chỉ bind loopback, tự thoát sau 120 giây; trả `simulated` thay vì gọi API nguồn. Test mode không lưu mã, không bật startup, không gọi shutdown/Sleep. Không dùng mã ghép nối thật cho test.

API Microsoft: https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-setsuspendstate và https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown

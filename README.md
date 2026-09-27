# Wake My PC

Ứng dụng Flutter Android/iOS để bật máy tính trong mạng nội bộ, triển khai từ `srs/v1.md`.

## Chức năng

- Giao diện tiếng Việt; thiết lập 5 bước và hướng dẫn BIOS/Windows.
- Tự nhận IPv4, subnet và broadcast Wi-Fi, không yêu cầu quyền vị trí để đọc SSID.
- Quét LAN theo nhóm tối đa 12 thiết bị, có tiến độ và dừng quét.
- Nhập MAC thủ công; thử đọc ARP trên Android nếu hệ điều hành cho phép.
- Lưu nhiều PC, sửa/xóa có xác nhận, chọn máy mặc định, lưu lịch sử 60 hoạt động.
- Gửi Magic Packet UDP thật, cấu hình số lần gửi/cổng/thời gian chờ.
- Theo dõi phản hồi, chẩn đoán và cảnh báo khi subnet thay đổi.
- Không tài khoản, backend, quảng cáo hay tự động bật PC.

## Chạy

Đã phát triển với Flutter 3.47.5 / Dart 3.13.4. Cần Android SDK và Java tương thích với Flutter.

```sh
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --debug
```

Trên máy Windows hiện tại, Flutter nằm ở `C:\Users\HOANGTHAO\develop\flutter\bin\flutter.bat`.
APK thử nghiệm: `build/app/outputs/flutter-apk/app-debug.apk`.

## iOS

Mã nguồn iOS và mô tả quyền Mạng cục bộ đã được cấu hình. Cần **macOS, Xcode, thiết bị iPhone và Apple signing team** để build/kiểm thử:

```sh
flutter pub get
flutter build ios --no-codesign
# Chọn Team trong Xcode, sau đó chạy trên iPhone hoặc build IPA:
flutter build ipa
```

`ios/Runner/Runner.entitlements` khai báo `com.apple.developer.networking.multicast` vì Wake-on-LAN dùng UDP broadcast. Apple yêu cầu entitlement này cho broadcast/multicast trên iOS; cần được Apple cấp và có trong provisioning profile. Xem [tài liệu Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast). Chưa build/kiểm thử iOS trên Windows; không có IPA trong bản bàn giao này.

## Giới hạn cần biết

- PC cần hỗ trợ và đã bật Wake-on-LAN, còn nguồn, ưu tiên Ethernet. Hãy thử từ Sleep trước.
- Quét và kiểm tra trạng thái dùng kết nối TCP trên cổng 445, 3389, 22, 80. Thiết bị chặn/không mở các cổng này có thể không xuất hiện; không phản hồi được hiển thị là **Chưa xác định**, không khẳng định đã tắt.
- Quét tối đa phần /24 chứa điện thoại trên mạng lớn hơn /24. Không tự quét LAN khi mở app; chỉ kiểm tra IP đã lưu.
- iOS không cung cấp MAC của thiết bị khác qua API công khai; Android mới thường chặn ARP. Nhập MAC là phương án dự phòng có chủ đích. Không suy đoán MAC hoặc tên PC từ địa chỉ IP.
- Nhận phản hồi xác nhận IP đang truy cập được, không xác minh đó là cùng MAC. Nên đặt DHCP reservation cho PC để IP ổn định.
- Đổi subnet cần cập nhật PC qua Chi tiết / Quét lại. Hai Wi-Fi khác nhau có cùng subnet không phân biệt được vì app không thu thập SSID/BSSID.
- Chưa hỗ trợ Wake qua Internet, widget, QR, cloud hoặc backup/export.
- APK debug dành cho thử nghiệm. Bản phát hành cửa hàng cần khóa ký riêng; cấu hình release mẫu hiện dùng debug key, chưa sẵn sàng đưa lên Play Store.

## Kiến trúc

- `lib/models.dart`: thiết bị, kiểm tra MAC/IPv4, subnet, Magic Packet.
- `lib/services.dart`: UDP/TCP, quét giới hạn concurrency, dữ liệu local.
- `lib/setup.dart`: wizard và sửa thông tin máy.
- `lib/screens.dart`: home, hoạt động, Wake progress, diagnostics, help.
- `test/`: kiểm thử gói UDP qua loopback, subnet, dữ liệu và luồng giao diện.
- `scripts/generate-icons.ps1`: tạo lại biểu tượng hình học cho hai nền tảng.

## Kiểm thử trên phần cứng

1. Cài app lên điện thoại cùng LAN với PC có WoL.
2. Thêm PC bằng MAC Ethernet và IP thật; đối chiếu `ipconfig /all`.
3. Cho PC Sleep, bấm BẬT PC, xác nhận PC thức dậy bằng quan sát trực tiếp.
4. Thử firewall chặn kiểm tra: app không được báo chắc chắn PC đã tắt.
5. Thử tắt Wi-Fi, đổi mạng, từ chối quyền iOS, hủy quét và dừng theo dõi.
6. Khởi động lại app để kiểm tra dữ liệu lưu bền vững.

Gói UDP được kiểm thử bằng socket loopback; điều đó không thay thế việc xác nhận PC vật lý thức dậy.

## Giao diện và font

Giao diện dùng nền sáng, thẻ PC xanh đen, điểm nhấn mint/lavender, menu dạng bottom sheet, bộ lọc yêu thích và thanh điều hướng nổi.

Font **Be Vietnam Pro** được đóng gói trực tiếp trong app (400–900), không tải từ Internet lúc chạy. Font do nhóm tác giả Việt thiết kế và tinh chỉnh dấu tiếng Việt: https://github.com/bettergui/BeVietnamPro . Nguồn Google Fonts và revision được ghi tại `assets/fonts/SOURCE.txt`; giấy phép SIL OFL 1.1 được giữ nguyên tại `assets/fonts/OFL.txt` và đăng ký với Flutter LicenseRegistry.

## Bật trực tiếp trên Home

Nhấn BẬT PC để gửi tín hiệu ngay từ thẻ máy. App báo đã gửi, khóa nút của máy đó để tránh gửi lặp và kiểm tra phản hồi sau 10 giây. Có phản hồi: thông báo PC đã khởi động thành công/đang phản hồi. Chưa có phản hồi: tự chuyển tab Trợ giúp với thông tin máy và hướng dẫn; không khẳng định PC chắc chắn đã tắt. Nếu chưa lưu IP, cần bổ sung IP để xác nhận. Kiểm tra này hoạt động khi app còn chạy; hệ điều hành có thể trì hoãn tác vụ khi app ở nền.

Bảng màu hiện tại: nền xám lạnh, thẻ xanh đen chuyển sắc, xanh điện cho điều hướng, cyan cho nút bật máy.

## Windows Agent — Sleep và tắt máy

Tải bộ `dist/WakeMyPcAgent.zip`, giải nén và chạy `WakeMyPcAgent.exe` trên PC. Xem [hướng dẫn Agent](windows-agent/README.md) để mở firewall Private TCP 47991 và ghép nối.

Trong app, mở menu của PC → **Ghép nối Windows Agent**. Sau khi xác thực mã, Home hiển thị **Sleep** và **Tắt máy**. Cả hai có xác nhận trước khi gửi; PC chờ 10 giây và có thể hủy qua thông báo trên điện thoại hoặc biểu tượng tray Windows. Agent dùng DPAPI, điện thoại dùng secure storage; không lưu mã vào danh sách PC.

Agent có tùy chọn tự chạy khi đăng nhập Windows. Bản này không phải Windows Service. Lệnh nguồn đã được kiểm thử bằng chế độ mô phỏng qua TCP thật; không thực hiện tắt/Sleep máy phát triển trong quá trình kiểm thử.

## Home tối giản theo máy mặc định

### Giao diện Điều khiển (xem trước)

Mở **Điều khiển · Xem trước** trên Home hoặc **Điều khiển** trong menu. Có ba tab: Touchpad (con trỏ mẫu, nhấp/kéo và tốc độ), Touch Bar (media, âm lượng, phím tắt, F1–F12), Bàn phím (nhập tiếng Việt, phím bổ trợ và touchpad nhỏ). Các thao tác chỉ cập nhật giao diện và phản hồi rung, chưa gửi lệnh đến Windows Agent. Không cần PC online để thử giao diện.

### Trạng thái máy

Giao diện sáng/tối hiện dùng chung cho toàn app. Công tắc mặt trời/mặt trăng trên thanh trên cùng đổi màu Home, Danh sách, Trợ giúp và các màn mở tiếp theo. Đổi giao diện không thay đổi trạng thái PC; nút Điều khiển trên Home vẫn chỉ hiện khi máy được xác nhận đã bật. Lựa chọn màu được giữ trong phiên app.

- Chọn duy nhất một ngôi sao tại tab **Danh sách** để máy xuất hiện trên **Home**. Chưa chọn máy thì Home hướng dẫn chọn; không tự lấy máy khác thay thế.
- Chưa có phản hồi: nền đen, nút bật tròn. Không phản hồi không đồng nghĩa chắc chắn PC đã tắt.
- Đã xác nhận PC hoạt động: nền sáng, hai nút Sleep và Shutdown. Nếu chưa ghép Agent, các nút dẫn tới ghép nối.
- App kiểm tra trạng thái mỗi 15 giây khi ở foreground và khi quay lại app. Sau lệnh Wake vẫn kiểm tra sau khoảng 10 giây.
- Nếu kiểm tra sau Wake chưa nhận phản hồi, popup hỏi **PC đã bật chưa?**: **Đã bật** chuyển Home sang nền sáng; **Chưa bật** mở Trợ giúp. Xác nhận thủ công có nhãn riêng, giữ trong phiên app cho đến khi có phản hồi thật hoặc Agent nhận lệnh Sleep/Shutdown; không bị xóa bởi lần kiểm tra không phản hồi tiếp theo.
- Tab Hoạt động được thay bằng Danh sách; lịch sử truy cập từ menu.
- Ảnh `docs/home-dark.png`, `docs/home-light.png`, `docs/device-list.png` được render từ widget thật với trạng thái giả lập để kiểm tra bố cục, không phải bằng chứng PC vật lý bật/tắt.

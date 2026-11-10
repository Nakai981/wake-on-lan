import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'design.dart';

const agentDownloadUrl =
    'https://github.com/Nakai981/wake-on-lan/releases/latest/download/WakeMyPcAgent.exe';

class AgentHelpPage extends StatelessWidget {
  const AgentHelpPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trợ giúp Windows Agent')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: const AgentHelpContent(),
      ),
    ),
  );
}

class AgentHelpContent extends StatelessWidget {
  const AgentHelpContent({super.key});

  Future<void> open(BuildContext context, String address) async {
    try {
      if (await launchUrl(
        Uri.parse(address),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the guide available when no browser can handle the link.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không mở được trình duyệt. Hãy thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: uiFont),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          height: 1.65,
          color: colors.onSurface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.desktop_windows_rounded,
              size: 44,
              color: colors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Cài Agent trên máy tính Windows',
              style: TextStyle(
                fontFamily: uiFont,
                fontSize: 18,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Agent giúp điện thoại ghép nối bằng QR, điều khiển chuột/phím, Sleep và tắt PC. '
              'Chỉ bật PC bằng Wake-on-LAN thì không bắt buộc cài Agent.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: colors.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dùng trong LAN Wi-Fi/Ethernet. Không theo dõi hoạt động máy tính, không gửi dữ liệu lên cloud.',
                      style: TextStyle(
                        height: 1.5,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => open(context, agentDownloadUrl),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Tải Windows Agent (.exe)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: agentDownloadUrl),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Đã sao chép link tải. Gửi link này sang PC Windows.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Sao chép link tải cho PC'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tải từ GitHub Releases chính thức. Hãy mở trang này trên PC Windows để tải '
              'và chạy WakeMyPcAgent.exe. Chỉ cần một file EXE, không cần giải nén.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 20),
            const Text(
              '1. Kết nối điện thoại với Wi-Fi cùng mạng LAN của PC. PC có thể dùng Wi-Fi hoặc Ethernet.\n\n'
              '2. Mở WakeMyPcAgent.exe trên PC. Nếu Windows hỏi quyền mạng, chỉ cho phép trên mạng Private tin cậy; Agent dùng TCP 47991.\n\n'
              '3. Bấm “Hiện QR ghép nối”, chọn card mạng đang kết nối. Để bật PC bằng Wake-on-LAN, ưu tiên MAC Ethernet có hỗ trợ Wake.\n\n'
              '4. Trên điện thoại, mở Thêm máy tính, chọn QR Agent, quét mã rồi bấm Hoàn tất để xác thực.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bạn giữ quyền kiểm soát',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Không theo dõi hoạt động sử dụng máy: không ghi màn hình, ghi âm, lưu phím gõ hay lịch sử duyệt web.\n\n'
                    '• Không có tài khoản, quảng cáo hay dịch vụ thu thập dữ liệu. Danh sách PC và lịch sử lệnh được lưu trên điện thoại.\n\n'
                    '• Điều khiển qua mạng nội bộ Wi-Fi/Ethernet, không cần máy chủ cloud. Internet chỉ cần khi bạn tải bản phát hành từ GitHub.\n\n'
                    '• Không phải công cụ xâm nhập. Lệnh điều khiển phải được xác thực bằng mã ghép nối của bạn. QR chứa mã này: chỉ quét trên thiết bị của bạn và không chia sẻ ảnh QR.\n\n'
                    '• Bạn chủ động chọn chạy cùng Windows, đổi mã để thu hồi ghép nối hoặc chọn Thoát Agent ở khay hệ thống. Sleep/Tắt máy dùng thời gian chờ đã lưu (mặc định 10 giây) và có thể hủy khi còn đang chờ.\n\n'
                    'Chỉ dùng trong LAN tin cậy; không chuyển tiếp cổng 47991 ra Internet. Kết nối Wi-Fi để điều khiển không đồng nghĩa PC hỗ trợ đánh thức qua Wi-Fi; Wake phụ thuộc card mạng, BIOS và driver.',
                    style: TextStyle(
                      height: 1.6,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  open(context, 'https://github.com/Nakai981/wake-on-lan'),
              icon: const Icon(Icons.code_rounded),
              label: const Text('Xem mã nguồn trên GitHub'),
            ),
          ],
        ),
      ),
    );
  }
}

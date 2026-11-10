import 'package:flutter/material.dart';

import 'agent_help.dart';
import 'design.dart';
import 'siri_help.dart';

class HelpContent extends StatelessWidget {
  final bool embedded, openSiri;
  final String? notice;
  const HelpContent({
    super.key,
    this.embedded = false,
    this.openSiri = false,
    this.notice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Apply one Vietnamese font and a consistent reading scale to every topic,
    // including Agent help, in both light and dark appearances.
    final readingTheme = theme.copyWith(
      textTheme: theme.textTheme
          .apply(fontFamily: uiFont)
          .copyWith(
            bodyMedium: TextStyle(
              fontFamily: uiFont,
              fontSize: 14,
              height: 1.65,
              color: colors.onSurface,
            ),
            bodyLarge: TextStyle(
              fontFamily: uiFont,
              fontSize: 15,
              height: 1.65,
              color: colors.onSurface,
            ),
            titleLarge: TextStyle(
              fontFamily: uiFont,
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
      expansionTileTheme: ExpansionTileThemeData(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: colors.primary,
        collapsedIconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        collapsedTextColor: colors.onSurface,
      ),
    );
    final content = Theme(
      data: readingTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                notice!,
                style: TextStyle(
                  fontFamily: uiFont,
                  fontSize: 14,
                  height: 1.65,
                  color: colors.onTertiaryContainer,
                ),
              ),
            ),
          if (!embedded) ...[
            Text(
              'Hướng dẫn sử dụng',
              style: TextStyle(
                fontFamily: uiFont,
                fontSize: 26,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thiết lập PC, dùng Siri và xử lý kết nối.',
              style: TextStyle(
                fontFamily: uiFont,
                fontSize: 14,
                height: 1.6,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
          ],
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Theme(
              data: readingTheme.copyWith(
                colorScheme: colors.copyWith(
                  onSurfaceVariant: colors.onSurface,
                ),
              ),
              child: _HelpTopic(
                key: PageStorageKey('siri-guide-$openSiri'),
                title: 'Siri trên iPhone',
                subtitle: 'Thiết lập, câu lệnh và quyền Shortcuts',
                icon: Icons.mic_none_rounded,
                initiallyExpanded: openSiri,
                child: const SiriHelpContent(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Máy tính & kết nối',
            style: TextStyle(
              fontFamily: uiFont,
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const _HelpTopic(
                  title: 'Windows Agent',
                  subtitle: 'Cài đặt, ghép nối và quyền riêng tư',
                  icon: Icons.desktop_windows_rounded,
                  child: AgentHelpContent(),
                ),
                for (final guide in _guides) ...[
                  Divider(
                    height: 1,
                    indent: 18,
                    endIndent: 18,
                    color: colors.outlineVariant,
                  ),
                  _HelpTopic(
                    title: guide.$1,
                    icon: guide.$2,
                    child: Text(
                      guide.$3,
                      style: TextStyle(
                        fontFamily: uiFont,
                        fontSize: 14,
                        height: 1.7,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return embedded
        ? content
        : SingleChildScrollView(
            key: const PageStorageKey('help-scroll'),
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
            child: content,
          );
  }
}

class _HelpTopic extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;
  const _HelpTopic({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey('help-topic-$title'),
    initiallyExpanded: initiallyExpanded,
    leading: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
    title: Text(
      title,
      style: TextStyle(
        fontFamily: uiFont,
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: TextStyle(
              fontFamily: uiFont,
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
    children: [Align(alignment: Alignment.centerLeft, child: child)],
  );
}

const _guides = [
  (
    'Wake-on-LAN là gì?',
    Icons.bolt_outlined,
    'Bật máy tính bằng tín hiệu gửi qua mạng nội bộ. PC cần còn cắm nguồn và card mạng '
        'hỗ trợ Wake-on-LAN. Điện thoại phải kết nối cùng mạng với PC; chưa hỗ trợ bật từ 4G/5G.',
  ),
  (
    'Chuẩn bị BIOS / UEFI',
    Icons.memory_rounded,
    'Vào BIOS / UEFI, tìm Wake on LAN, Power On by PCI-E hoặc Resume by LAN và bật. '
        'Tên mục tùy hãng và model. ErP / Deep Sleep có thể ngắt nguồn card mạng khi tắt máy; '
        'kiểm tra hướng dẫn của nhà sản xuất.',
  ),
  (
    'Thiết lập Windows',
    Icons.window_rounded,
    'Mở Device Manager, chọn Network adapters, chọn card Ethernet rồi mở Properties. Trong Advanced, '
        'bật Wake on Magic Packet nếu có. Trong Power Management, cho phép thiết bị đánh thức '
        'máy và chỉ đánh thức bằng Magic Packet. Hãy thử từ Sleep trước; bật từ trạng thái '
        'tắt hoàn toàn phụ thuộc phần cứng và driver.',
  ),
  (
    'Tìm địa chỉ MAC và IP',
    Icons.fingerprint_rounded,
    'Trên PC, mở Command Prompt và nhập ipconfig /all. Ở card Ethernet đang cắm dây, '
        'Physical Address là MAC, IPv4 Address là IP. Nhập MAC dạng AA-BB-CC-DD-EE-FF '
        'hoặc AA:BB:CC:DD:EE:FF. Không dùng MAC của adapter VPN.',
  ),
  (
    'Không tìm thấy PC khi quét?',
    Icons.wifi_find_rounded,
    'Giữ PC đang bật, cùng Wi-Fi/LAN và tránh Wi-Fi khách. Kiểm tra Client Isolation trên '
        'router. Bộ quét dò các cổng 47991, 445, 3389, 22 và 80; firewall có thể chặn '
        'phản hồi. Bạn vẫn có thể thêm PC thủ công.',
  ),
  (
    'Đã gửi tín hiệu nhưng PC chưa bật?',
    Icons.power_settings_new_rounded,
    'Kiểm tra nguồn, dây LAN, đúng MAC Ethernet và cấu hình Wake-on-LAN trong BIOS/Windows. '
        'Đã gửi tín hiệu chưa có nghĩa PC đã bật; app chỉ xác nhận khi nhận được phản hồi. '
        'Nếu chưa có phản hồi, hãy quan sát PC trực tiếp.',
  ),
  (
    'Quyền mạng & dữ liệu',
    Icons.shield_outlined,
    'Trên iPhone, cho phép Local Network khi hệ thống hỏi. Nếu đã từ chối, bật lại trong '
        'Cài đặt, chọn Quyền riêng tư & Bảo mật rồi mở Mạng cục bộ. Danh sách PC và lịch sử được '
        'lưu trên thiết bị. App không yêu cầu tài khoản.',
  ),
];

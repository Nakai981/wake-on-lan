import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

class SiriHelpContent extends StatelessWidget {
  const SiriHelpContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = TextStyle(
      fontFamily: uiFont,
      fontSize: 14,
      height: 1.65,
      color: colors.onSurfaceVariant,
    );
    Widget paragraph(String text) => Text(text, style: body);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: uiFont,
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        paragraph(
          'Dùng iPhone iOS 16 trở lên và chọn ngôn ngữ Siri là English.',
        ),
        heading('Thiết lập lần đầu'),
        const _SiriStep(
          number: '1',
          title: 'Chọn PC mặc định',
          detail: 'Trong Danh sách, chọn ngôi sao của PC muốn điều khiển.',
        ),
        const _SiriStep(
          number: '2',
          title: 'Kiểm tra kết nối',
          detail: 'Dùng cùng Wi-Fi/LAN, cho phép Local Network và thử Bật PC trong app.',
        ),
        const _SiriStep(
          number: '3',
          title: 'Mở các hành động có sẵn',
          detail:
              'Mở menu ba chấm, chọn Không gian của bạn, cuộn tới Thiết lập Siri rồi bấm Shortcuts. '
              'Mở trang này không gửi lệnh PC.',
        ),
        heading('Nói với Siri'),
        paragraph('Bạn có thể dùng ngay các câu có tên ứng dụng dưới đây.'),
        const SizedBox(height: 12),
        const _SiriCommand(
          label: 'Bật PC',
          command: 'Siri, wake with Wake My PC.',
        ),
        const _SiriCommand(
          label: 'Cho PC ngủ',
          command: 'Siri, sleep with Wake My PC.',
        ),
        const _SiriCommand(
          label: 'Tắt PC',
          command: 'Siri, shut down with Wake My PC.',
        ),
        const _SiriCommand(
          label: 'Hủy lệnh đang chờ',
          command: 'Siri, cancel power with Wake My PC.',
        ),
        heading('Dùng câu ngắn như “PC On”'),
        paragraph(
          'Trong Shortcuts, tạo phím tắt mới, chọn Add Action, mở Apps rồi chọn Wake My PC. '
          'Chọn một hành động rồi đặt tên phím tắt như dưới đây. Sau khi lưu, nói “Siri, PC On” hoặc tên tương ứng.',
        ),
        const SizedBox(height: 12),
        for (final item in const [
          ('PC On', 'Turn on my PC'),
          ('PC Sleep', 'Put my PC to sleep'),
          ('PC Off', 'Shut down my PC'),
          ('Cancel PC', 'Cancel PC power command'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.$1,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                Text('Chọn hành động: ${item.$2}', style: body),
              ],
            ),
          ),
        heading('Shortcuts hỏi “Allow”?'),
        paragraph(
          'Chạy phím tắt bằng tay một lần. Nếu có Always Allow, chọn để ghi nhớ '
          'quyền đó thay vì Allow Once. Nếu chỉ có Allow, cần bạn cấp quyền trên iPhone. '
          'App không thể tự chấp nhận hoặc tắt hộp thoại quyền của iOS.',
        ),
        heading('Khi chạy lệnh'),
        paragraph(
          'Siri mở app và có thể yêu cầu mở khóa iPhone. Sleep, Shutdown và hủy lệnh '
          'cần Windows Agent đã ghép nối. Sleep và Shutdown cần '
          'xác nhận rồi mới gửi; dùng thời gian chờ đã lưu trong Không gian của bạn. '
          'Hủy lệnh chỉ thành công khi Agent còn liên lạc được và lệnh vẫn đang chờ.',
        ),
        const SizedBox(height: 12),
        paragraph(
          '“Đã gửi tín hiệu” chưa có nghĩa PC đã bật. Nếu không nhận phản hồi, '
          'kiểm tra PC trực tiếp trước khi thử lại.',
        ),
      ],
    );
  }
}

class _SiriStep extends StatelessWidget {
  final String number, title, detail;
  const _SiriStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                fontFamily: uiFont,
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w700,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontSize: 14,
                    height: 1.65,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SiriCommand extends StatelessWidget {
  final String label, command;
  const _SiriCommand({required this.label, required this.command});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontSize: 12,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  key: PageStorageKey('siri-command-$label'),
                  command,
                  style: TextStyle(
                    fontFamily: uiFont,
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sao chép lệnh: $label',
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép câu lệnh Siri.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

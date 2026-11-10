import 'package:flutter/material.dart';

import 'design.dart';
import 'siri_setup.dart';

class WorkspaceSheet extends StatefulWidget {
  static const scrollKey = ValueKey('workspace-scroll');
  final String powerDelay;
  final int deviceCount;
  final bool canAddDevice, showSiri;
  final ValueChanged<String> onSelect;

  const WorkspaceSheet({
    super.key,
    required this.powerDelay,
    required this.deviceCount,
    required this.canAddDevice,
    required this.showSiri,
    required this.onSelect,
  });

  @override
  State<WorkspaceSheet> createState() => _WorkspaceSheetState();
}

class _WorkspaceSheetState extends State<WorkspaceSheet> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
              child: Row(
                children: [
                  const IconTile(Icons.tune_rounded, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Không gian của bạn',
                      style: TextStyle(
                        fontFamily: uiFont,
                        fontSize: 20,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng menu',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                child: ListView(
                  key: WorkspaceSheet.scrollKey,
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  children: [
                    _heading(context, 'Máy tính'),
                    _row(
                      context,
                      'powerDelay',
                      Icons.timer_outlined,
                      'Thời gian chờ tắt / Sleep',
                      'Dùng chung · ${widget.powerDelay}',
                    ),
                    _row(
                      context,
                      'controls',
                      Icons.touch_app_rounded,
                      'Điều khiển',
                      'Touchpad, Touch Bar và bàn phím',
                    ),
                    _row(
                      context,
                      'add',
                      Icons.add_rounded,
                      'Thêm máy tính',
                      'Quét mạng, nhập thủ công hoặc quét QR',
                      enabled: widget.canAddDevice,
                    ),
                    _row(
                      context,
                      'devices',
                      Icons.dns_outlined,
                      'Máy tính của tôi',
                      '${widget.deviceCount} thiết bị đã lưu',
                    ),
                    if (widget.showSiri) ...[
                      const SizedBox(height: 16),
                      SiriSetupCard(
                        showHelp: () => widget.onSelect('siriHelp'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _heading(context, 'Ứng dụng'),
                    _row(
                      context,
                      'history',
                      Icons.history_rounded,
                      'Lịch sử hoạt động',
                      'Các lệnh và lần gửi tín hiệu gần đây',
                    ),
                    _row(
                      context,
                      'refresh',
                      Icons.wifi_find_rounded,
                      'Kiểm tra kết nối',
                      'Cập nhật mạng và trạng thái PC',
                    ),
                    _row(
                      context,
                      'help',
                      Icons.help_outline_rounded,
                      'Hướng dẫn & trợ giúp',
                      'Wake-on-LAN, Siri và Windows Agent',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dữ liệu được lưu trên thiết bị. Không cần tài khoản.',
                            style: TextStyle(
                              fontFamily: uiFont,
                              fontSize: 12,
                              height: 1.6,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: uiFont,
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _row(
    BuildContext context,
    String id,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
      leading: IconTile(icon, size: 38),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontFamily: uiFont,
          fontSize: 12,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () => widget.onSelect(id),
    ),
  );
}

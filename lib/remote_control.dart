import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'touch_surface.dart';

/// Local interaction preview. No commands are sent to the Windows Agent yet.
class RemoteControlPage extends StatefulWidget {
  final String? pcName;
  const RemoteControlPage({super.key, this.pcName});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  final input = TextEditingController();
  final modifiers = <String>{};
  bool expanded = false;
  final functionScroll = ScrollController();
  final quickScroll = ScrollController();
  double volume = .55, sensitivity = 1;
  bool playing = false, isMuted = false;

  String feedback = 'Sẵn sàng trải nghiệm';

  @override
  void dispose() {
    input.dispose();
    functionScroll.dispose();
    quickScroll.dispose();
    super.dispose();
  }

  void respond(String value) {
    HapticFeedback.selectionClick();
    setState(() => feedback = value);
  }

  void submitText() {
    if (input.text.trim().isEmpty) return;
    respond(
      'Đã thử nhập ${input.text.characters.length} ký tự · chưa gửi đến PC',
    );
  }

  Widget functionKey(String label) {
    final selected = modifiers.contains(label);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          foregroundColor: selected ? scheme.primary : scheme.onSurface,
          backgroundColor: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () {
          if (['Ctrl', 'Alt', 'Shift', 'Win'].contains(label)) {
            setState(() {
              if (!modifiers.add(label)) modifiers.remove(label);
            });
            respond(
              modifiers.isEmpty
                  ? 'Đã nhả phím bổ trợ'
                  : 'Giữ ${modifiers.join(' + ')}',
            );
          } else {
            respond([...modifiers, label].join(' + '));
            setState(modifiers.clear);
          }
        },
        child: Text(label),
      ),
    );
  }

  Widget quickAction(String label, IconData icon, [VoidCallback? action]) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: IconButton.filledTonal(
          tooltip: label,
          iconSize: 19,
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: action ?? () => respond(label),
          icon: Icon(icon),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Điều khiển'),
        actions: [
          IconButton(
            tooltip: 'Xoay ngang touchpad',
            onPressed: openLandscapePad,
            icon: const Icon(Icons.screen_rotation_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  '${widget.pcName ?? 'Touchpad'} · Xem trước',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        maxLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => submitText(),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Nhập ký tự…',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Thử nhập',
                            onPressed: input.text.trim().isEmpty
                                ? null
                                : submitText,
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: expanded ? 'Thu gọn công cụ' : 'Mở rộng công cụ',
                      onPressed: () => setState(() {
                        expanded = !expanded;
                        if (!expanded) modifiers.clear();
                      }),
                      icon: AnimatedRotation(
                        turns: expanded ? .5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more_rounded),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !expanded
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            Text(
                              'PHÍM CHỨC NĂNG',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.3,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 48,
                              child: Scrollbar(
                                controller: functionScroll,
                                thumbVisibility: true,
                                thickness: 2,
                                child: SingleChildScrollView(
                                  key: const ValueKey('function-strip'),
                                  controller: functionScroll,
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final key in [
                                        'Esc',
                                        for (var i = 1; i <= 12; i++) 'F$i',
                                        'Ctrl',
                                        'Alt',
                                        'Shift',
                                        'Win',
                                        'Tab',
                                        'Enter',
                                        'Backspace',
                                        'Delete',
                                        'Space',
                                        '←',
                                        '↑',
                                        '↓',
                                        '→',
                                        'A',
                                        'C',
                                        'V',
                                        'X',
                                        'Z',
                                      ])
                                        functionKey(key),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'TRUY CẬP NHANH',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.3,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 52,
                              child: Scrollbar(
                                controller: quickScroll,
                                thickness: 2,
                                child: SingleChildScrollView(
                                  controller: quickScroll,
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      quickAction(
                                        'Desktop',
                                        Icons.desktop_windows_outlined,
                                      ),
                                      quickAction(
                                        'Đổi cửa sổ',
                                        Icons.layers_outlined,
                                      ),
                                      quickAction(
                                        'Chụp màn hình',
                                        Icons.screenshot_monitor_rounded,
                                      ),
                                      quickAction(
                                        'Tìm kiếm',
                                        Icons.search_rounded,
                                      ),
                                      quickAction(
                                        'Bài trước',
                                        Icons.skip_previous_rounded,
                                      ),
                                      quickAction(
                                        playing ? 'Tạm dừng' : 'Phát',
                                        playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        () {
                                          setState(() => playing = !playing);
                                          respond(
                                            playing
                                                ? 'Phát nhạc thử'
                                                : 'Tạm dừng',
                                          );
                                        },
                                      ),
                                      quickAction(
                                        'Bài sau',
                                        Icons.skip_next_rounded,
                                      ),
                                      quickAction(
                                        isMuted ? 'Bật tiếng' : 'Tắt tiếng',
                                        isMuted
                                            ? Icons.volume_off_rounded
                                            : Icons.volume_up_rounded,
                                        () {
                                          setState(() => isMuted = !isMuted);
                                          respond(
                                            isMuted ? 'Tắt tiếng' : 'Bật tiếng',
                                          );
                                        },
                                      ),
                                      quickAction(
                                        'Giảm âm lượng',
                                        Icons.volume_down_rounded,
                                        () {
                                          setState(() {
                                            volume = (volume - .05).clamp(0, 1);
                                            isMuted = false;
                                          });
                                          respond(
                                            'Âm lượng ${(volume * 100).round()}%',
                                          );
                                        },
                                      ),
                                      quickAction(
                                        'Tăng âm lượng',
                                        Icons.volume_up_rounded,
                                        () {
                                          setState(() {
                                            volume = (volume + .05).clamp(0, 1);
                                            isMuted = false;
                                          });
                                          respond(
                                            'Âm lượng ${(volume * 100).round()}%',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
                TouchSurface(
                  height: 300,
                  sensitivity: sensitivity,
                  dragging: false,
                  onAction: (value) => setState(() => feedback = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Tốc độ con trỏ',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sensitivity.toStringAsFixed(1)}×',
                      style: TextStyle(fontSize: 12, color: colors.primary),
                    ),
                  ],
                ),
                Slider(
                  value: sensitivity,
                  min: .5,
                  max: 2,
                  divisions: 15,
                  label: '${sensitivity.toStringAsFixed(1)}×',
                  onChanged: (value) => setState(() => sensitivity = value),
                ),
                Text(
                  feedback,
                  key: const ValueKey('remote-feedback'),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Xem trước · Chưa gửi lệnh đến PC',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openLandscapePad() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0C1729),
          body: SafeArea(
            child: RotatedBox(
              quarterTurns: 1,
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Trở về dọc',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.screen_rotation_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Touchpad',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Xem trước',
                        style: TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(width: 20),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: LayoutBuilder(
                        builder: (_, bounds) => TouchSurface(
                          height: bounds.maxHeight,
                          sensitivity: sensitivity,
                          dragging: false,
                          onAction: (_) {},
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

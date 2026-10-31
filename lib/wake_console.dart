import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';

class WakeSession extends ChangeNotifier {
  final Pc pc;
  final List<String> lines = [];
  String phase = 'Đang gửi tín hiệu…';
  DateTime? readyAt;
  bool stopped = false, sent = false, online = false;
  WakeSession(this.pc);
  void log(String text) {
    final now = DateTime.now();
    lines.add(
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}  $text',
    );
    notifyListeners();
  }

  void update(String text) {
    phase = text;
    notifyListeners();
  }
}

class WakeConsolePage extends StatefulWidget {
  final WakeSession session;
  final VoidCallback confirmed, help;
  const WakeConsolePage({
    super.key,
    required this.session,
    required this.confirmed,
    required this.help,
  });
  @override
  State<WakeConsolePage> createState() => _WakeConsolePageState();
}

class _WakeConsolePageState extends State<WakeConsolePage> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Console · ${widget.session.pc.name}')),
    body: AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final s = widget.session;
        final remaining = s.readyAt?.difference(DateTime.now()).inSeconds ?? 0;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(s.phase, style: Theme.of(context).textTheme.titleMedium),
              if (remaining > 0 && !s.stopped && !s.online)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Chờ khởi động: ${remaining + 1} giây · Phản hồi sớm sẽ chuyển ngay',
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1320),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SelectableText(
                  s.lines.isEmpty ? 'Đang chuẩn bị…' : s.lines.join('\n\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFBFE7DB),
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (s.sent && !s.online) ...[
                FilledButton(
                  onPressed: widget.confirmed,
                  child: const Text('Bỏ qua — PC đã bật'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: widget.help,
                  child: const Text('PC chưa được bật'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng console'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

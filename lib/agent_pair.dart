import 'package:flutter/material.dart';

import 'agent_client.dart';
import 'models.dart';
import 'design.dart';

class AgentPairPage extends StatefulWidget {
  final Pc pc;
  const AgentPairPage({super.key, required this.pc});
  @override
  State<AgentPairPage> createState() => _AgentPairPageState();
}

class _AgentPairPageState extends State<AgentPairPage> {
  final code = TextEditingController();
  final client = const AgentClient();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> pair() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await client.pair(widget.pc, code.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : 'Không ghép nối được. Kiểm tra IP, mã, Agent đang chạy và Firewall Private TCP 47991.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ghép nối Windows Agent')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const IconTile(Icons.desktop_windows_rounded, size: 64),
        const SizedBox(height: 20),
        Text(widget.pc.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text(
          '1. Mở WakeMyPcAgent.exe trên PC.\n2. Cho phép Agent trên mạng Private.\n3. Sao chép mã ghép nối vào ô bên dưới.\n\nĐiện thoại và PC cần cùng mạng. Agent phải đang chạy để Sleep hoặc tắt máy.',
          style: TextStyle(color: muted, height: 1.8),
        ),
        const SizedBox(height: 20),
        Text(
          'IP máy tính: ${widget.pc.ip.isEmpty ? 'Chưa có — bổ sung trong Chi tiết máy' : widget.pc.ip}',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: code,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Mã ghép nối',
            helperText: '32 ký tự hiển thị trong Windows Agent',
          ),
        ),
        const SizedBox(height: 20),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: busy || widget.pc.ip.isEmpty ? null : pair,
          child: Text(busy ? 'Đang xác thực…' : 'Ghép nối'),
        ),
      ],
    ),
  );
}

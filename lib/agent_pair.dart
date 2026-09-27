import 'package:flutter/material.dart';

import 'agent_client.dart';
import 'models.dart';
import 'design.dart';
import 'pairing_qr.dart';
import 'pairing_scanner.dart';

class AgentPairPage extends StatefulWidget {
  final Pc pc;
  const AgentPairPage({super.key, required this.pc});
  @override
  State<AgentPairPage> createState() => _AgentPairPageState();
}

class _AgentPairPageState extends State<AgentPairPage> {
  final code = TextEditingController();
  final client = AgentClient();
  bool busy = false;
  String? error;
  String? scannedIp;
  Future<void> scan() async {
    final qr = await Navigator.push<PairingQr>(
      context,
      MaterialPageRoute(builder: (_) => const PairingScannerPage()),
    );
    if (!mounted || qr == null) return;
    if (qr.mac != normalizeMac(widget.pc.mac)) {
      setState(
        () => error = 'MAC trong QR khác PC này. Chọn đúng card mạng trên Agent hoặc chọn lại PC trong app.',
      );
      return;
    }
    setState(() {
      scannedIp = qr.ip;
      code.text = qr.key;
      error = null;
    });
  }

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
      final pc = widget.pc.copy(ip: scannedIp, agentPaired: true);
      await client.pair(pc, code.text);
      if (mounted) Navigator.pop(context, pc);
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
    appBar: AppBar(title: Text('Ghép nối Windows Agent')),
    body: ListView(
      padding: EdgeInsets.all(24),
      children: [
        IconTile(Icons.desktop_windows_rounded, size: 64),
        SizedBox(height: 20),
        Text(widget.pc.name, style: Theme.of(context).textTheme.headlineMedium),
        SizedBox(height: 12),
        Text(
          '1. Mở WakeMyPcAgent.exe trên PC.\n2. Cho phép Agent trên mạng Private.\n3. Sao chép mã ghép nối vào ô bên dưới.\n\nĐiện thoại và PC cần cùng mạng. Agent phải đang chạy để Sleep hoặc tắt máy.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.8,
          ),
        ),
        SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: busy ? null : scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Quét QR từ Windows Agent'),
        ),
        const SizedBox(height: 12),
        Text(
          'IP máy tính: ${scannedIp ?? (widget.pc.ip.isEmpty ? 'Chưa có — quét QR để điền IP' : widget.pc.ip)}',
        ),
        SizedBox(height: 16),
        TextField(
          controller: code,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Mã ghép nối',
            helperText: '32 ký tự hiển thị trong Windows Agent',
          ),
        ),
        SizedBox(height: 20),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: busy || (scannedIp ?? widget.pc.ip).isEmpty ? null : pair,
          child: Text(busy ? 'Đang xác thực…' : 'Ghép nối'),
        ),
      ],
    ),
  );
}

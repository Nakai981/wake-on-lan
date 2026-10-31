import 'package:flutter/material.dart';

import 'agent_client.dart';
import 'models.dart';
import 'pairing_qr.dart';
import 'pairing_scanner.dart';
import 'services.dart';
import 'agent_help.dart';

class SetupPage extends StatefulWidget {
  final NetworkService net;
  final Pc? existing;
  final AgentClient? agentClient;
  const SetupPage({
    super.key,
    required this.net,
    this.existing,
    this.agentClient,
  });
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      mac = TextEditingController(),
      ip = TextEditingController(),
      broadcast = TextEditingController(),
      port = TextEditingController(text: '9'),
      retries = TextEditingController(text: '3'),
      timeout = TextEditingController(text: '60'),
      startup = TextEditingController(text: '20');
  int mode = 2, done = 0, total = 0, generation = 0, metadataGeneration = 0;
  bool scanning = false, loading = false, saving = false;
  Lan? lan;
  String? error, info, autoName, autoMac;
  PairingQr? qr;
  final found = <String>[];
  @override
  void initState() {
    super.initState();
    final pc = widget.existing;
    if (pc != null) {
      mode = 1;
      name.text = pc.name;
      mac.text = pc.mac;
      ip.text = pc.ip;
      broadcast.text = pc.broadcast;
      port.text = '${pc.port}';
      retries.text = '${pc.retries}';
      timeout.text = '${pc.timeout}';
      startup.text = '${pc.startupDelay}';
    }
    checkNetwork();
  }

  @override
  void dispose() {
    generation++;
    metadataGeneration++;
    for (final c in [
      name,
      mac,
      ip,
      broadcast,
      port,
      retries,
      timeout,
      startup,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> checkNetwork() async {
    try {
      final value = await widget.net.network();
      if (mounted) setState(() => lan = value);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Chưa đọc được Wi-Fi. Bạn vẫn có thể nhập thủ công.',
        );
    }
  }

  void stopScan() {
    generation++;
    setState(() => scanning = false);
  }

  Future<void> scan() async {
    final run = ++generation;
    setState(() {
      scanning = true;
      error = null;
      found.clear();
      done = 0;
      total = 0;
    });
    await checkNetwork();
    if (!mounted || run != generation) return;
    if (lan == null) {
      setState(() {
        scanning = false;
        error = 'Kết nối Wi-Fi cùng LAN với PC.';
      });
      return;
    }
    try {
      await widget.net.scan(
        lan!,
        cancelled: () => !mounted || run != generation,
        progress: (n, count, address) {
          if (!mounted || run != generation) return;
          setState(() {
            done = n;
            total = count;
            if (address != null && !found.contains(address)) found.add(address);
          });
        },
      );
    } catch (_) {
      if (mounted && run == generation)
        setState(
          () => error =
              'Quét thất bại. Kiểm tra quyền Mạng cục bộ hoặc nhập thủ công.',
        );
    } finally {
      if (mounted && run == generation) setState(() => scanning = false);
    }
  }

  Future<void> metadata(String address, {bool keepMac = false}) async {
    final run = ++metadataGeneration;
    try {
      ipv4Number(address);
    } catch (_) {
      return;
    }
    setState(() {
      loading = true;
      info = 'Đang lấy tên máy và MAC…';
    });
    try {
      final values = await Future.wait([
        widget.net.nameFor(address),
        keepMac ? Future<String?>.value(null) : widget.net.macFor(address),
      ]);
      if (!mounted || run != metadataGeneration || ip.text != address) return;
      setState(() {
        if (values[0] != null && (name.text.isEmpty || name.text == autoName)) {
          name.text = values[0]!;
          autoName = values[0];
        }
        if (values[1] != null && (mac.text.isEmpty || mac.text == autoMac)) {
          mac.text = values[1]!;
          autoMac = values[1];
        }
        info = keepMac
            ? 'Đã điền IP và MAC từ QR. Bấm Hoàn tất để xác thực và lưu.'
            : values[1] == null
            ? 'Không đọc được MAC. Nhập MAC Ethernet hoặc dùng QR Windows Agent.'
            : 'Đã lấy MAC. Kiểm tra đúng card Ethernet dùng để Wake.';
      });
    } catch (_) {
      if (mounted && run == metadataGeneration)
        setState(
          () => info = 'Chưa lấy được tên/MAC. Bạn có thể nhập thủ công.',
        );
    } finally {
      if (mounted && run == metadataGeneration) setState(() => loading = false);
    }
  }

  Future<void> select(String address) async {
    setState(() {
      if (name.text == autoName) name.clear();
      if (mac.text == autoMac) mac.clear();
      ip.text = address;
      qr = null;
    });
    await metadata(address);
  }

  Future<void> scanQr() async {
    final value = await Navigator.push<PairingQr>(
      context,
      MaterialPageRoute(builder: (_) => const PairingScannerPage()),
    );
    if (!mounted || value == null) return;
    setState(() {
      qr = value;
      ip.text = value.ip;
      mac.text = value.mac;
      error = null;
      if (name.text.isEmpty || name.text == autoName) {
        name.text = 'PC ${value.ip}';
        autoName = name.text;
      }
    });
    await metadata(value.ip, keepMac: true);
  }

  String? validIp(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      ipv4Number(value.trim());
      return null;
    } catch (_) {
      return 'Nhập IPv4 hợp lệ.';
    }
  }

  bool number(TextEditingController c, int min, int max) {
    final n = int.tryParse(c.text);
    return n != null && n >= min && n <= max;
  }

  Future<void> save() async {
    if (saving || loading || !form.currentState!.validate()) return;
    if (!(validIp(broadcast.text) == null &&
        number(port, 1, 65535) &&
        number(retries, 1, 10) &&
        number(timeout, 5, 300) &&
        number(startup, 10, 30))) {
      setState(
        () => error = 'Kiểm tra cấu hình nâng cao: cổng, số lần gửi, broadcast và thời gian chờ.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final old = widget.existing;
      var pc = Pc(
        id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        mac: normalizeMac(mac.text),
        ip: ip.text.trim(),
        broadcast: broadcast.text.trim(),
        network: lan?.key ?? old?.network ?? '',
        port: int.parse(port.text),
        retries: int.parse(retries.text),
        timeout: int.parse(timeout.text),
        startupDelay: int.parse(startup.text),
        favorite: old?.favorite ?? false,
        agentPaired: old?.agentPaired ?? false,
        lastWake: old?.lastWake,
      );
      if (qr != null) {
        if (pc.mac != qr!.mac || pc.ip != qr!.ip)
          throw const FormatException(
            'Thông tin đã thay đổi. Hãy quét lại QR.',
          );
        await (widget.agentClient ?? const AgentClient()).pair(pc, qr!.key);
        pc = pc.copy(agentPaired: true);
      }
      if (mounted) Navigator.pop(context, pc);
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is FormatException ? e.message : 'Không xác thực được Agent. Kiểm tra IP, mã và firewall TCP 47991.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(
    String label,
    TextEditingController c, {
    String? hint,
    String? Function(String?)? validate,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      enabled: !saving,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validate,
      onChanged: c == ip || c == mac
          ? (_) {
              metadataGeneration++;
              setState(() {
                loading = false;
                qr = null;
                info = null;
              });
            }
          : null,
      onFieldSubmitted: c == ip ? (_) => metadata(ip.text.trim()) : null,
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Thêm máy tính' : 'Chỉnh sửa máy tính',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final option in const [
                        (2, 'QR Agent', Icons.qr_code_scanner),
                        (0, 'Quét LAN', Icons.radar),
                        (1, 'Nhập tay', Icons.edit_outlined),
                      ]) ...[
                        if (option.$1 != 2) const SizedBox(width: 8),
                        Expanded(
                          child: Semantics(
                            selected: mode == option.$1,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 4,
                                ),
                                backgroundColor: mode == option.$1
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: saving
                                  ? null
                                  : () {
                                      stopScan();
                                      setState(() {
                                        mode = option.$1;
                                        error = null;
                                      });
                                    },
                              child: Column(
                                children: [
                                  Icon(option.$3),
                                  const SizedBox(height: 8),
                                  Text(option.$2, textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (mode == 0) ...[
                    Text(
                      lan == null
                          ? 'Kết nối Wi-Fi cùng LAN với PC.'
                          : 'Wi-Fi: ${lan!.ip} · ${lan!.mask}',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : scanning
                          ? stopScan
                          : scan,
                      icon: Icon(scanning ? Icons.stop : Icons.radar),
                      label: Text(
                        scanning
                            ? 'Dừng quét'
                            : total > 0
                            ? 'Quét lại'
                            : 'Quét LAN',
                      ),
                    ),
                    if (scanning || total > 0) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: total == 0 ? null : done / total,
                      ),
                      Text(
                        '$done/$total địa chỉ · ${found.length} thiết bị phản hồi',
                      ),
                    ],
                    if (found.isNotEmpty)
                      SizedBox(
                        height: 180,
                        child: ListView(
                          children: found
                              .map(
                                (address) => Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.computer),
                                    title: Text(address),
                                    selected: ip.text == address,
                                    trailing: ip.text == address
                                        ? const Icon(Icons.check_circle)
                                        : null,
                                    onTap: saving
                                        ? null
                                        : () => select(address),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Chọn IP để thử lấy tên và MAC. Kết quả có thể gồm router/điện thoại.',
                      ),
                    ),
                  ],
                  if (mode == 2) ...[
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Thêm PC bằng QR Agent',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Trên PC, mở Windows Agent → Hiện QR ghép nối. Chọn Wi-Fi hoặc Ethernet đang kết nối, rồi quét mã bằng điện thoại. Ưu tiên Ethernet để bật PC bằng Wake-on-LAN.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: saving ? null : scanQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Quét QR Windows Agent'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () {
                              stopScan();
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => const AgentHelpPage(),
                                ),
                              );
                            },
                      icon: const Icon(Icons.help_outline_rounded),
                      label: const Text('Chưa có Agent? Trợ giúp'),
                    ),
                    if (qr != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Đã đọc QR. Hoàn tất sẽ xác thực Agent trước khi lưu.',
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                  field(
                    'Tên máy tính',
                    name,
                    hint: 'PC của tôi',
                    validate: (v) => v == null || v.trim().isEmpty
                        ? 'Nhập tên máy tính.'
                        : null,
                  ),
                  field(
                    'Địa chỉ IP',
                    ip,
                    hint: '192.168.0.100',
                    validate: validIp,
                  ),
                  OutlinedButton.icon(
                    onPressed: loading || saving || ip.text.isEmpty
                        ? null
                        : () => metadata(ip.text.trim(), keepMac: qr != null),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      loading ? 'Đang lấy thông tin…' : 'Tự lấy tên & MAC',
                    ),
                  ),
                  if (info != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(info!),
                    ),
                  if (info == null) const SizedBox(height: 16),
                  field(
                    'MAC Ethernet',
                    mac,
                    hint: 'A4:BB:6D:12:34:56',
                    validate: (v) {
                      try {
                        normalizeMac(v ?? '');
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const Text(
                    'Nếu IP dùng Wi-Fi, hãy kiểm tra MAC Ethernet dùng để Wake. Trên PC: ipconfig /all → Physical Address.',
                  ),
                  ExpansionTile(
                    title: const Text('Cấu hình nâng cao'),
                    children: [
                      field(
                        'Broadcast',
                        broadcast,
                        hint: lan?.broadcast,
                        validate: validIp,
                      ),
                      field('Cổng UDP', port, numeric: true),
                      field('Số lần gửi (1–10)', retries, numeric: true),
                      field(
                        'Chờ khởi động (10–30 giây)',
                        startup,
                        numeric: true,
                      ),
                      field(
                        'Theo dõi phản hồi (5–300 giây)',
                        timeout,
                        numeric: true,
                      ),
                    ],
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: saving || loading ? null : save,
                    child: Text(saving ? 'Đang xác thực…' : 'Hoàn tất'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

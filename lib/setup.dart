import 'package:flutter/material.dart';

import 'models.dart';
import 'services.dart';
import 'main.dart';
import 'design.dart';
import 'screens.dart';

class SetupPage extends StatefulWidget {
  final NetworkService net;
  final Pc? existing;
  const SetupPage({super.key, required this.net, this.existing});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      mac = TextEditingController(),
      ip = TextEditingController(),
      broadcast = TextEditingController();
  final port = TextEditingController(text: '9'),
      retries = TextEditingController(text: '3'),
      timeout = TextEditingController(text: '60');
  int step = 0, done = 0, total = 0;
  bool checking = false,
      scanning = false,
      cancelled = false,
      scanned = false,
      selecting = false;
  Lan? lan;
  String? error;
  final List<String> found = [];
  @override
  void initState() {
    super.initState();
    final pc = widget.existing;
    if (pc != null) {
      step = 3;
      name.text = pc.name;
      mac.text = pc.mac;
      ip.text = pc.ip;
      broadcast.text = pc.broadcast;
      port.text = '${pc.port}';
      retries.text = '${pc.retries}';
      timeout.text = '${pc.timeout}';
    }
    checkNetwork();
  }

  @override
  void dispose() {
    cancelled = true;
    for (final c in [name, mac, ip, broadcast, port, retries, timeout]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> checkNetwork() async {
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final current = await widget.net.network();
      if (mounted) setState(() => lan = current);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Chưa đọc được thông tin mạng. Kiểm tra Wi-Fi rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> scan() async {
    await checkNetwork();
    if (!mounted || lan == null) return;
    setState(() {
      scanning = true;
      cancelled = false;
      scanned = false;
      done = 0;
      total = lan!.hosts.length;
      found.clear();
    });
    try {
      await widget.net.scan(
        lan!,
        cancelled: () => cancelled || !mounted,
        progress: (n, count, address) {
          if (mounted) {
            setState(() {
              done = n;
              total = count;
              if (address != null) found.add(address);
            });
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Chưa quét được mạng. Cho phép truy cập Mạng cục bộ hoặc nhập máy thủ công.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          scanning = false;
          scanned = true;
        });
      }
    }
  }

  Future<void> select(String address) async {
    setState(() => selecting = true);
    final detected = await widget.net.macFor(address);
    if (!mounted) return;
    setState(() {
      ip.text = address;
      if (detected != null) mac.text = detected;
      selecting = false;
      step = 3;
    });
    if (detected == null) {
      message(
        context,
        'Chưa đọc được MAC. Bạn chỉ cần nhập thông tin này một lần.',
      );
    }
  }

  String? validIp(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      ipv4Number(value.trim());
      return null;
    } catch (_) {
      return 'Nhập địa chỉ IPv4 hợp lệ.';
    }
  }

  String? validNumber(String? value, int min, int max) {
    final n = int.tryParse(value ?? '');
    return n == null || n < min || n > max ? 'Nhập số từ $min đến $max.' : null;
  }

  void next() {
    if (step == 3) {
      final advancedValid =
          validIp(broadcast.text) == null &&
          validNumber(port.text, 1, 65535) == null &&
          validNumber(retries.text, 1, 10) == null &&
          validNumber(timeout.text, 5, 120) == null;
      if (!advancedValid) {
        setState(
          () => error = 'Mở Cài đặt nâng cao và kiểm tra broadcast, cổng, số lần gửi hoặc thời gian chờ.',
        );
        form.currentState!.validate();
        return;
      }
      if (!form.currentState!.validate()) return;
    }
    error = null;
    setState(() => step++);
  }

  void save() {
    final old = widget.existing;
    Navigator.pop(
      context,
      Pc(
        id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        mac: normalizeMac(mac.text),
        ip: ip.text.trim(),
        broadcast: broadcast.text.trim(),
        network: lan?.key ?? old?.network ?? '',
        port: int.parse(port.text),
        retries: int.parse(retries.text),
        timeout: int.parse(timeout.text),
        favorite: old?.favorite ?? false,
        agentPaired: old?.agentPaired ?? false,
        lastWake: old?.lastWake,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null ? 'Thêm máy tính' : 'Chi tiết máy tính',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: SetupStepper(step: step),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    Text(
                      [
                        'Kết nối trước nhé',
                        'Chuẩn bị máy tính',
                        'Tìm PC của bạn',
                        'Làm quen với PC',
                        'Sẵn sàng đánh thức',
                      ][step],
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 14),
                    if (step == 0) ...[
                      const Text(
                        'Kết nối điện thoại với Wi-Fi cùng mạng với PC. Nên cắm dây LAN cho máy tính.',
                        style: TextStyle(height: 1.7, color: muted),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(
                                lan != null
                                    ? Icons.wifi_rounded
                                    : Icons.wifi_off_rounded,
                                size: 48,
                                color: green,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                checking
                                    ? 'Đang kiểm tra…'
                                    : lan != null
                                    ? 'Đã kết nối Wi-Fi'
                                    : 'Chưa nhận được mạng Wi-Fi',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                lan == null
                                    ? 'Bật Wi-Fi rồi kiểm tra lại.'
                                    : 'Mạng: ${ipv4String(lan!.network)}',
                                style: const TextStyle(color: muted),
                              ),
                              TextButton(
                                onPressed: checking ? null : checkNetwork,
                                child: const Text('Kiểm tra lại'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Wake My PC cần truy cập mạng cục bộ để tìm và bật máy. Khi hệ thống hỏi, hãy chọn Cho phép. Thông tin máy chỉ được lưu trên điện thoại.',
                        style: TextStyle(height: 1.7, color: muted),
                      ),
                    ],
                    if (step == 1) ...[
                      const Text(
                        'Chỉ cần thực hiện một lần trên PC. Giữ máy đang bật trong lúc tìm thiết bị.',
                        style: TextStyle(height: 1.7, color: muted),
                      ),
                      const SizedBox(height: 20),
                      const HelpContent(embedded: true),
                    ],
                    if (step == 2) ...[
                      const Text(
                        'Giữ PC đang bật và cùng mạng. Chọn địa chỉ của máy trong kết quả, hoặc thêm thủ công nếu không tìm thấy.',
                        style: TextStyle(height: 1.7, color: muted),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: scanning || selecting ? null : scan,
                        icon: const Icon(Icons.radar_rounded),
                        label: Text(
                          scanning ? 'Đang tìm thiết bị…' : 'Quét mạng',
                        ),
                      ),
                      if (scanning) ...[
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: total == 0 ? null : done / total,
                        ),
                        const SizedBox(height: 8),
                        Text('Đã kiểm tra $done / $total'),
                        TextButton(
                          onPressed: () => setState(() => cancelled = true),
                          child: const Text('Dừng quét'),
                        ),
                      ],
                      if (scanned && found.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'Chưa tìm thấy thiết bị phản hồi. PC có thể chặn kiểm tra kết nối; bạn vẫn có thể thêm bằng MAC.',
                          ),
                        ),
                      ...found.map(
                        (address) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.computer_rounded,
                            color: green,
                          ),
                          title: const Text('Thiết bị trong mạng'),
                          subtitle: Text(address),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: scanning || selecting
                              ? null
                              : () => select(address),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Quét tối đa 254 địa chỉ gần điện thoại. Kết quả có thể bao gồm router và thiết bị khác; đối chiếu IPv4 trong ipconfig /all trên PC.',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                    if (step == 3)
                      Form(
                        key: form,
                        child: Column(
                          children: [
                            const Text(
                              'Đặt một tên dễ nhớ. MAC là địa chỉ card mạng của PC, chỉ cần nhập một lần.',
                              style: TextStyle(height: 1.7, color: muted),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: name,
                              textCapitalization: TextCapitalization.sentences,
                              maxLength: 40,
                              decoration: const InputDecoration(
                                labelText: 'Tên máy tính',
                                hintText: 'Ví dụ: PC Gaming',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Hãy đặt tên cho máy tính.'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: mac,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Địa chỉ MAC',
                                hintText: 'A4:BB:6D:12:34:56',
                              ),
                              validator: (v) {
                                try {
                                  normalizeMac(v ?? '');
                                  return null;
                                } on FormatException catch (e) {
                                  return e.message;
                                }
                              },
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => const SafeArea(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                        'Trên PC Windows, mở Command Prompt → nhập ipconfig /all.\n\nTrong card Ethernet đang cắm dây, sao chép Physical Address vào ô MAC. IPv4 Address là địa chỉ IP.\n\nVí dụ: A4-BB-6D-12-34-56',
                                        style: TextStyle(height: 1.8),
                                      ),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.help_outline, size: 18),
                                label: const Text('Cách tìm MAC'),
                              ),
                            ),
                            TextFormField(
                              controller: ip,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Địa chỉ IP (không bắt buộc)',
                                helperText:
                                    'Giúp kiểm tra PC đã hoạt động hay chưa.',
                              ),
                              validator: validIp,
                            ),
                            TextButton.icon(
                              onPressed: () => setState(() => step = 2),
                              icon: const Icon(Icons.radar),
                              label: const Text('Tìm / quét lại máy tính'),
                            ),
                            ExpansionTile(
                              maintainState: true,
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Cài đặt nâng cao'),
                              children: [
                                TextFormField(
                                  controller: broadcast,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Broadcast',
                                    hintText:
                                        lan?.broadcast ??
                                        'Tự động theo mạng Wi-Fi',
                                    helperText:
                                        'Để trống để tự động nhận diện.',
                                  ),
                                  validator: validIp,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: port,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Cổng UDP',
                                  ),
                                  validator: (v) => validNumber(v, 1, 65535),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: retries,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Số lần gửi tín hiệu',
                                  ),
                                  validator: (v) => validNumber(v, 1, 10),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'App tự kiểm tra PC sau khoảng 10 giây kể từ khi gửi tín hiệu.',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (step == 4) ...[
                      const SizedBox(height: 12),
                      const Icon(
                        Icons.task_alt_rounded,
                        size: 84,
                        color: green,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        name.text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Lưu máy rồi cho PC chuyển sang Sleep. Từ màn hình chính, nhấn BẬT PC để kiểm tra Wake-on-LAN.',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.7, color: muted),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'App sẽ gửi tín hiệu và theo dõi phản hồi nếu bạn đã nhập IP. PC cần được cấu hình Wake-on-LAN và vẫn cắm nguồn.',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.7, color: muted),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    if (step > 0) ...[
                      IconButton(
                        tooltip: 'Bước trước',
                        onPressed: scanning || selecting
                            ? null
                            : () => setState(() => step--),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            scanning ||
                                selecting ||
                                (step == 0 && (checking || lan == null))
                            ? null
                            : step == 4
                            ? save
                            : next,
                        child: Text(
                          [
                            'Tiếp tục',
                            'Tôi đã chuẩn bị xong',
                            'Nhập máy thủ công',
                            'Tiếp tục',
                            'Lưu máy tính',
                          ][step],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

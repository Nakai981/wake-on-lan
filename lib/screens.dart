import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'design.dart';
import 'models.dart';
import 'services.dart';
import 'setup.dart';
import 'agent_client.dart';
import 'agent_pair.dart';

String stamp(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${date.day}/${date.month}';
void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class HomePage extends StatefulWidget {
  final DeviceStore store;
  final NetworkService net;
  final AgentClient? agentClient;
  const HomePage({
    super.key,
    required this.store,
    required this.net,
    this.agentClient,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  AgentClient get agent => widget.agentClient ?? const AgentClient();
  final Set<String> powerBusy = {};
  final Set<String> onlineIds = {};
  Timer? statusTimer;

  Future<bool> pcReachable(Pc pc) async {
    if (!pc.agentPaired) return widget.net.reachable(pc.ip);
    try {
      return await agent.command(pc, 'status') == 'online';
    } catch (_) {
      return false;
    }
  }

  Future<void> pairAgent(Pc pc) async {
    final paired = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AgentPairPage(pc: pc)),
    );
    if (!mounted || paired != true) return;
    try {
      await persist(
        pcs.map((p) => p.id == pc.id ? p.copy(agentPaired: true) : p).toList(),
      );
      if (mounted) {
        message(
          context,
          'Đã ghép nối. Bạn có thể Sleep hoặc tắt PC ngay trên Home.',
        );
      }
    } catch (_) {
      if (mounted) message(context, 'Chưa lưu được ghép nối. Hãy thử lại.');
    }
  }

  Future<void> power(Pc pc, String command) async {
    if (powerBusy.contains(pc.id) || waking.contains(pc.id)) return;
    final label = command == 'sleep' ? 'Sleep' : 'Tắt máy';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label ${pc.name}?'),
        content: Text(
          command == 'shutdown'
              ? 'Lưu công việc trên PC trước khi tắt. Windows Agent sẽ chờ 10 giây để bạn có thể hủy.'
              : 'PC sẽ chuyển sang Sleep sau 10 giây. Bạn có thể bật lại bằng Wake-on-LAN nếu đã cấu hình.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => powerBusy.add(pc.id));
    try {
      final result = await agent.command(pc, command);
      if (!mounted) return;
      if (result != 'accepted') {
        message(
          context,
          result == 'busy'
              ? 'PC đang có một lệnh chờ. Hủy lệnh trước khi gửi lại.'
              : 'Agent chưa nhận lệnh.',
        );
        return;
      }
      setState(() => statuses[pc.id] = 'Đã gửi lệnh $label');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: Text('PC đã nhận lệnh $label, sẽ thực hiện sau 10 giây.'),
            action: SnackBarAction(
              label: 'Hủy lệnh',
              onPressed: () => cancelPower(pc),
            ),
          ),
        );
      try {
        await widget.store.log('Đã gửi lệnh $label · ${pc.name}');
      } catch (_) {}
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Chưa xác nhận được lệnh. Kiểm tra Agent, IP và mã ghép nối. Nếu mất kết nối sau khi gửi, hãy kiểm tra hoặc hủy trên PC.',
        );
      }
    } finally {
      if (mounted) setState(() => powerBusy.remove(pc.id));
    }
  }

  Future<void> cancelPower(Pc pc) async {
    try {
      final result = await agent.command(pc, 'cancel');
      if (mounted) {
        message(
          context,
          result == 'cancelled'
              ? 'Đã hủy lệnh còn đang chờ trên PC.'
              : 'Chưa hủy được lệnh.',
        );
      }
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Không liên lạc được với Agent để hủy. Lệnh có thể đã thực hiện.',
        );
      }
    }
  }

  List<Pc> pcs = [];
  final Map<String, String> statuses = {};
  Lan? lan;
  int tab = 0;
  bool refreshing = false, storageError = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      pcs = widget.store.read();
    } catch (_) {
      storageError = true;
    }
    refresh();
    statusTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        refresh();
      }
    });
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    for (final timer in wakeTimers.values) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      final current = await widget.net.network();
      if (!mounted) return;
      setState(() => lan = current);
      for (final pc in List<Pc>.of(pcs)) {
        if (!mounted) return;
        if (waking.contains(pc.id)) continue;
        setState(() => statuses[pc.id] = 'Đang kiểm tra…');
        final online =
            current != null &&
            pc.ip.isNotEmpty &&
            current.contains(pc.ip) &&
            await pcReachable(pc);
        if (!mounted) return;
        setState(() {
          if (!waking.contains(pc.id)) {
            statuses[pc.id] = online ? 'Đang hoạt động' : 'Chưa xác định';
            if (online) {
              onlineIds.add(pc.id);
            } else {
              onlineIds.remove(pc.id);
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          lan = null;
          onlineIds.clear();
          for (final pc in pcs) {
            statuses[pc.id] = 'Chưa xác định';
          }
        });
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> persist(List<Pc> next) async {
    await widget.store.save(next);
    if (mounted) setState(() => pcs = next);
  }

  Future<void> edit([Pc? pc]) async {
    final result = await Navigator.of(context).push<Pc>(
      MaterialPageRoute(
        builder: (_) => SetupPage(net: widget.net, existing: pc),
      ),
    );
    if (result == null || !mounted) return;
    if (pcs.any((p) => p.mac == result.mac && p.id != result.id)) {
      message(context, 'Máy có địa chỉ MAC này đã được lưu.');
      return;
    }
    try {
      await persist([...pcs.where((p) => p.id != result.id), result]);
      if (!mounted) return;
      message(context, 'Đã lưu ${result.name}. Bạn có thể thử bật máy.');
      refresh();
    } catch (_) {
      if (mounted) message(context, 'Không lưu được máy. Hãy thử lại.');
    }
  }

  final Set<String> waking = {};
  final Map<String, Timer> wakeTimers = {};
  String? wakeHelp;

  void notifyWake(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> wake(Pc pc) async {
    if (waking.contains(pc.id)) return;
    setState(() {
      waking.add(pc.id);
      statuses[pc.id] = 'Đang gửi tín hiệu…';
    });
    try {
      final current = await widget.net.network();
      if (!mounted) return;
      if (current == null) {
        throw StateError('Kết nối Wi-Fi cùng mạng với PC để bật máy.');
      }
      if (pc.network.isNotEmpty && pc.network != current.key) {
        throw StateError(
          'Mạng đã thay đổi. Mở Chi tiết / Quét lại để cập nhật máy.',
        );
      }
      await widget.net.wake(pc, current);
      if (!mounted) return;
      setState(() => statuses[pc.id] = 'Đã gửi · kiểm tra sau 10 giây');
      notifyWake('Đã gửi tín hiệu khởi động đến ${pc.name}.');
      wakeTimers[pc.id] = Timer(
        const Duration(seconds: 10),
        () => checkWake(pc, current),
      );
      try {
        await persist(
          pcs
              .map((p) => p.id == pc.id ? p.copy(lastWake: DateTime.now()) : p)
              .toList(),
        );
        await widget.store.log('Đã gửi tín hiệu khởi động · ${pc.name}');
      } catch (_) {
        /* Sending succeeded even if local history cannot be saved. */
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        waking.remove(pc.id);
        statuses[pc.id] = 'Chưa gửi được tín hiệu';
      });
      notifyWake(
        error is StateError
            ? error.message.toString()
            : 'Chưa gửi được tín hiệu. Kiểm tra Wi-Fi và quyền mạng cục bộ.',
      );
    }
  }

  Future<void> checkWake(Pc pc, Lan sentNetwork) async {
    wakeTimers.remove(pc.id);
    if (!mounted || !pcs.any((p) => p.id == pc.id)) return;
    var online = false;
    String? reason;
    try {
      final current = await widget.net.network();
      if (pc.ip.isEmpty) {
        reason = 'Máy chưa có IP để kiểm tra. Mở Chi tiết máy và bổ sung địa chỉ IP.';
      } else if (current == null ||
          current.key != sentNetwork.key ||
          !current.contains(pc.ip)) {
        reason = 'Kết nối mạng đã thay đổi hoặc IP của PC không cùng mạng.';
      } else {
        online = await pcReachable(pc)
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
      }
    } catch (_) {
      reason =
          'Chưa kiểm tra được kết nối. Kiểm tra Wi-Fi và quyền mạng cục bộ.';
    }
    if (!mounted || !pcs.any((p) => p.id == pc.id)) return;
    setState(() {
      waking.remove(pc.id);
      if (online) {
        onlineIds.add(pc.id);
      } else {
        onlineIds.remove(pc.id);
      }
      statuses[pc.id] = online ? 'Đang hoạt động' : 'Chưa xác nhận khởi động';
      if (!online) {
        wakeHelp =
            '${pc.name}: đã gửi tín hiệu nhưng chưa xác nhận được máy đã khởi động sau khoảng 10 giây. ${reason ?? 'PC có thể cần thêm thời gian hoặc đang chặn kiểm tra kết nối.'}';
        tab = 2;
      }
    });
    notifyWake(
      online
          ? '${pc.name} đã khởi động thành công — PC đang phản hồi.'
          : 'Chưa xác nhận được ${pc.name} đã bật. Xem hướng dẫn kiểm tra.',
    );
    try {
      await widget.store.log(
        '${online ? 'PC đã phản hồi' : 'Chưa xác nhận khởi động'} · ${pc.name}',
      );
    } catch (_) {
      /* Keep the observed result. */
    }
  }

  Future<void> action(String value, Pc pc) async {
    if (value == 'pair') {
      await pairAgent(pc);
      return;
    }
    if (value == 'cancelPower') {
      await cancelPower(pc);
      return;
    }
    if (value == 'edit') {
      await edit(pc);
      return;
    }
    if (value == 'diagnose') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DiagnosticsPage(pc: pc, net: widget.net),
        ),
      );
      return;
    }
    try {
      if (value == 'favorite') {
        await persist(pcs.map((p) => p.copy(favorite: p.id == pc.id)).toList());
      } else if (value == 'delete') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Xóa “${pc.name}”?'),
            content: const Text('Thông tin bật máy sẽ bị xóa khỏi điện thoại.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Xóa'),
              ),
            ],
          ),
        );
        if (yes == true) {
          if (pc.agentPaired) await agent.forget(pc.id);
          await persist(pcs.where((p) => p.id != pc.id).toList());
        }
      }
    } catch (_) {
      if (mounted) message(context, 'Không lưu được thay đổi. Hãy thử lại.');
    }
  }

  Future<void> openMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  IconTile(Icons.power_settings_new_rounded),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Không gian của bạn',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              menuRow(
                ctx,
                'add',
                Icons.add_rounded,
                'Thêm máy tính',
                'Thiết lập một PC mới',
                enabled: !storageError,
              ),
              menuRow(
                ctx,
                'devices',
                Icons.dashboard_outlined,
                'Máy tính của tôi',
                '${pcs.length} thiết bị đã lưu',
              ),
              menuRow(
                ctx,
                'history',
                Icons.history_rounded,
                'Lịch sử hoạt động',
                'Các lần gửi tín hiệu gần đây',
              ),
              menuRow(
                ctx,
                'refresh',
                Icons.wifi_find_rounded,
                'Kiểm tra kết nối',
                'Cập nhật mạng và trạng thái PC',
              ),
              menuRow(
                ctx,
                'help',
                Icons.auto_stories_outlined,
                'Hướng dẫn & trợ giúp',
                'Thiết lập, kết nối và khắc phục lỗi',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: accent, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Riêng tư từ thiết kế.\nKhông tài khoản, không máy chủ.',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'WAKE MY PC  /  1.0',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'add':
        await edit();
      case 'devices':
        setState(() {
          tab = 1;
        });
      case 'history':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Lịch sử hoạt động')),
              body: history(),
            ),
          ),
        );
      case 'help':
        setState(() => tab = 2);
      case 'refresh':
        await refresh();
    }
  }

  Widget menuRow(
    BuildContext ctx,
    String id,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      tileColor: Colors.white,
      leading: IconTile(icon, size: 42),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: muted),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: muted, size: 20),
      onTap: () => Navigator.pop(ctx, id),
    ),
  );

  Future<void> deviceMenu(Pc pc) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconTile(Icons.desktop_windows_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      pc.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              menuRow(
                ctx,
                'pair',
                Icons.link_rounded,
                'Ghép nối Windows Agent',
                pc.agentPaired
                    ? 'Ghép nối lại / cập nhật mã'
                    : 'Bật tính năng Sleep và tắt máy',
              ),
              if (pc.agentPaired)
                menuRow(
                  ctx,
                  'cancelPower',
                  Icons.cancel_outlined,
                  'Hủy lệnh nguồn',
                  'Hủy lệnh đang chờ trên PC',
                ),
              menuRow(
                ctx,
                'edit',
                Icons.tune_rounded,
                'Chi tiết / Quét lại',
                'Tên máy và thông tin kết nối',
              ),
              menuRow(
                ctx,
                'diagnose',
                Icons.fact_check_outlined,
                'Kiểm tra cấu hình',
                'Chẩn đoán khả năng bật máy',
              ),
              menuRow(
                ctx,
                'favorite',
                Icons.star_outline_rounded,
                'Đặt làm máy mặc định',
                'Hiển thị máy này trên Home',
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFCE3956),
                ),
                title: const Text(
                  'Xóa máy',
                  style: TextStyle(
                    color: Color(0xFFCE3956),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && choice != null) await action(choice, pc);
  }

  Pc? get selectedPc {
    for (final pc in pcs) {
      if (pc.favorite) return pc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pc = selectedPc;
    final online = pc != null && onlineIds.contains(pc.id);
    final dark = tab == 0 && !online;
    final foreground = dark ? Colors.white : navy;
    final background = dark ? Colors.black : paper;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                systemNavigationBarColor: Colors.black,
              )
            : SystemUiOverlayStyle.dark,
        toolbarHeight: 60,
        title: Text(
          tab == 0
              ? 'wake'
              : tab == 1
              ? 'Danh sách máy'
              : 'Trợ giúp',
          style: TextStyle(
            color: foreground,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Kiểm tra lại',
            onPressed: refreshing ? null : refresh,
            icon: Icon(
              Icons.refresh_rounded,
              color: dark ? Colors.white60 : muted,
            ),
          ),
          IconButton(
            tooltip: 'Mở menu',
            onPressed: openMenu,
            icon: Icon(Icons.more_horiz_rounded, color: foreground),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: tab == 1
                  ? deviceList()
                  : tab == 2
                  ? HelpContent(key: const ValueKey('help'), notice: wakeHelp)
                  : controlHome(pc, online),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? const Color(0xFF1D1D1D) : soft,
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: uiFont,
            fontSize: 11,
            color: dark
                ? (states.contains(WidgetState.selected)
                      ? Colors.white
                      : Colors.white54)
                : (states.contains(WidgetState.selected) ? accent : muted),
          ),
        ),
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.power_settings_new_rounded,
              color: dark ? Colors.white70 : muted,
            ),
            selectedIcon: Icon(
              Icons.power_settings_new_rounded,
              color: foreground,
            ),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.dns_outlined,
              color: dark ? Colors.white54 : muted,
            ),
            selectedIcon: const Icon(Icons.dns_rounded, color: accent),
            label: 'Danh sách',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.help_outline_rounded,
              color: dark ? Colors.white54 : muted,
            ),
            selectedIcon: const Icon(Icons.help_rounded, color: accent),
            label: 'Trợ giúp',
          ),
        ],
      ),
    );
  }

  Widget controlHome(Pc? pc, bool online) {
    final foreground = online ? navy : Colors.white;
    final secondary = online ? muted : Colors.white54;
    final busy =
        pc != null && (waking.contains(pc.id) || powerBusy.contains(pc.id));
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: ValueKey('control-${pc?.id}-$online'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (pc == null) ...[
                  const Icon(
                    Icons.star_outline_rounded,
                    color: Colors.white38,
                    size: 44,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Chọn một máy cho Home',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    storageError
                        ? 'Không đọc được dữ liệu đã lưu. Hãy khởi động lại app.'
                        : 'Đánh dấu sao một máy trong Danh sách\nđể điều khiển ngay tại đây.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary, height: 1.7),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: () => setState(() => tab = 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: const Text('Chọn máy tính'),
                  ),
                ] else ...[
                  Text(
                    pc.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    online
                        ? 'Đang hoạt động'
                        : waking.contains(pc.id)
                        ? (statuses[pc.id] ?? 'Đang gửi tín hiệu…')
                        : refreshing
                        ? 'Đang kiểm tra…'
                        : 'Chưa nhận được phản hồi',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                  const SizedBox(height: 48),
                  if (!online) ...[
                    SizedBox(
                      width: 152,
                      height: 152,
                      child: FilledButton(
                        onPressed: busy ? null : () => wake(pc),
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFFF4F7FA),
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFF202020),
                          disabledForegroundColor: Colors.white38,
                        ),
                        child: Icon(
                          busy
                              ? Icons.hourglass_top_rounded
                              : Icons.power_settings_new_rounded,
                          size: 58,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      busy ? 'ĐÃ GỬI TÍN HIỆU' : 'BẬT PC',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: homePowerButton(
                            pc,
                            'sleep',
                            Icons.bedtime_outlined,
                            'Sleep',
                            busy,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: homePowerButton(
                            pc,
                            'shutdown',
                            Icons.power_settings_new_rounded,
                            'Shutdown',
                            busy,
                          ),
                        ),
                      ],
                    ),
                    if (!pc.agentPaired) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Ghép nối Windows Agent để dùng Sleep và Shutdown.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      TextButton(
                        onPressed: () => pairAgent(pc),
                        child: const Text('Ghép nối Agent'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 36),
                  TextButton(
                    onPressed: () => setState(() => tab = 1),
                    style: TextButton.styleFrom(foregroundColor: secondary),
                    child: const Text(
                      'Đổi máy tính',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget homePowerButton(
    Pc pc,
    String command,
    IconData icon,
    String label,
    bool busy,
  ) => SizedBox(
    height: 136,
    child: FilledButton(
      onPressed: busy
          ? null
          : () => pc.agentPaired ? power(pc, command) : pairAgent(pc),
      style: FilledButton.styleFrom(
        backgroundColor: command == 'sleep' ? Colors.white : navy,
        foregroundColor: command == 'sleep' ? navy : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 18),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  Widget deviceList() => ListView(
    key: const ValueKey('devices'),
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Một dấu sao. Một máy trên Home.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Thêm máy tính',
            onPressed: storageError ? null : () => edit(),
            icon: const Icon(Icons.add_rounded, color: accent),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (pcs.isEmpty) empty(),
      ...pcs.map(
        (pc) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
              leading: IconButton(
                tooltip: pc.favorite
                    ? 'Máy đang hiển thị trên Home'
                    : 'Chọn ${pc.name} cho Home',
                onPressed: () => action('favorite', pc),
                icon: Icon(
                  pc.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: pc.favorite ? accent : muted,
                ),
              ),
              title: Text(
                pc.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                statuses[pc.id] ?? 'Chưa xác định',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              trailing: IconButton(
                tooltip: 'Tùy chọn máy',
                onPressed: () => deviceMenu(pc),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
              onTap: pc.favorite
                  ? () => setState(() => tab = 0)
                  : () => edit(pc),
            ),
          ),
        ),
      ),
    ],
  );

  Widget empty() => Container(
    decoration: BoxDecoration(
      color: navy,
      gradient: panelGradient,
      borderRadius: BorderRadius.circular(24),
    ),
    padding: const EdgeInsets.all(22),
    child: Column(
      children: [
        const IconTile(
          Icons.desktop_windows_rounded,
          color: mint,
          background: Color(0xFF20354D),
          size: 58,
        ),
        const SizedBox(height: 18),
        const Text(
          'PC của bạn, trong tầm tay',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Thêm PC để bật máy chỉ với một chạm.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB4C5D9), fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: storageError ? null : () => edit(),
            style: FilledButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: navy,
              minimumSize: const Size(48, 50),
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Bắt đầu thiết lập'),
          ),
        ),
      ],
    ),
  );

  Widget deviceCard(Pc pc) {
    final changed =
        lan != null && pc.network.isNotEmpty && lan!.key != pc.network;
    final online = statuses[pc.id] == 'Đang hoạt động';
    return Container(
      decoration: BoxDecoration(
        color: navy,
        gradient: panelGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                Icons.desktop_windows_rounded,
                color: Color(0xFF7DD3FC),
                background: Color(0xFF20354D),
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pc.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 5,
                          color: online ? mint : const Color(0xFFF4C76B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statuses[pc.id] ?? 'Chưa xác định',
                            style: const TextStyle(
                              color: Color(0xFFB4C5D9),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (pc.favorite)
                const Tooltip(
                  message: 'Máy mặc định',
                  child: Icon(
                    Icons.star_rounded,
                    color: Color(0xFFF4C76B),
                    size: 16,
                  ),
                ),
              IconButton(
                tooltip: 'Tùy chọn máy',
                onPressed: () => deviceMenu(pc),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Color(0xFFB4C5D9),
                  size: 22,
                ),
              ),
            ],
          ),
          if (changed)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Mạng đã thay đổi. Vào Chi tiết / Quét lại để cập nhật.',
                style: TextStyle(
                  color: Color(0xFFF4C76B),
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: waking.contains(pc.id) || powerBusy.contains(pc.id)
                  ? null
                  : () => wake(pc),
              style: FilledButton.styleFrom(
                backgroundColor: mint,
                foregroundColor: navy,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.power_settings_new_rounded, size: 20),
              label: Text(
                waking.contains(pc.id) ? 'ĐANG XỬ LÝ…' : 'BẬT PC',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ),
          ),
          if (pc.agentPaired) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        waking.contains(pc.id) || powerBusy.contains(pc.id)
                        ? null
                        : () => power(pc, 'sleep'),
                    icon: const Icon(Icons.bedtime_outlined, size: 17),
                    label: const Text('Sleep'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB4C5D9),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        waking.contains(pc.id) || powerBusy.contains(pc.id)
                        ? null
                        : () => power(pc, 'shutdown'),
                    icon: const Icon(Icons.power_settings_new, size: 17),
                    label: const Text('Tắt máy'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFDA4AF),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (pc.lastWake != null) ...[
            const SizedBox(height: 10),
            Text(
              'Gửi gần nhất: ${stamp(pc.lastWake!)}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CAFC6)),
            ),
          ],
        ],
      ),
    );
  }

  Widget history() {
    final entries = widget.store.history();
    return ListView(
      key: const ValueKey('history'),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      children: [
        const SectionTitle(
          'Hoạt động gần đây',
          'Mỗi lần kết nối, đều được ghi nhớ.',
        ),
        if (entries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                children: [
                  const IconTile(Icons.history_rounded, size: 64),
                  const SizedBox(height: 20),
                  const Text(
                    'Một khởi đầu mới',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Lịch sử sẽ xuất hiện tại đây\nsau khi bạn gửi tín hiệu bật PC.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, height: 1.7),
                  ),
                  const SizedBox(height: 22),
                  TextButton(
                    onPressed: () => setState(() => tab = 0),
                    child: const Text('Về máy tính của tôi'),
                  ),
                ],
              ),
            ),
          ),
        ...entries.map((entry) {
          final split = entry.indexOf('|');
          final date = split < 0
              ? null
              : DateTime.tryParse(entry.substring(0, split));
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: const IconTile(Icons.bolt_rounded, size: 40),
                title: Text(
                  split < 0 ? entry : entry.substring(split + 1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    date == null ? '' : stamp(date),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class WakePage extends StatefulWidget {
  final Pc pc;
  final NetworkService net;
  final Future<void> Function() onSent, onOnline;
  const WakePage({
    super.key,
    required this.pc,
    required this.net,
    required this.onSent,
    required this.onOnline,
  });
  @override
  State<WakePage> createState() => _WakePageState();
}

class _WakePageState extends State<WakePage> {
  bool busy = true, success = false;
  String text = 'Đang kiểm tra mạng…';
  int elapsed = 0, generation = 0;
  @override
  void initState() {
    super.initState();
    run();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> run() async {
    final token = ++generation;
    bool active() => mounted && token == generation;
    setState(() {
      busy = true;
      success = false;
      elapsed = 0;
      text = 'Đang kiểm tra mạng…';
    });
    try {
      final lan = await widget.net.network();
      if (!active()) return;
      if (lan == null) {
        throw StateError('Hãy kết nối Wi-Fi cùng mạng với PC rồi thử lại.');
      }
      if (widget.pc.network.isNotEmpty && widget.pc.network != lan.key) {
        throw StateError(
          'Mạng đã thay đổi. Hãy mở Chi tiết / Quét lại để cập nhật máy trước khi bật.',
        );
      }
      setState(() => text = 'Đang gửi tín hiệu Wake-on-LAN…');
      await widget.net.wake(widget.pc, lan);
      if (!active()) return;
      try {
        await widget.onSent();
      } catch (_) {
        if (mounted && active()) {
          message(context, 'Đã gửi tín hiệu nhưng chưa lưu được lịch sử.');
        }
      }
      if (!active()) return;
      if (widget.pc.ip.isEmpty) {
        setState(
          () => text = 'Đã gửi tín hiệu. Thêm địa chỉ IP trong Chi tiết để theo dõi máy khởi động.',
        );
        return;
      }
      setState(() => text = 'Đang chờ PC khởi động…');
      final watch = Stopwatch()..start();
      while (active() && watch.elapsed.inSeconds < widget.pc.timeout) {
        final online = await widget.net.reachable(widget.pc.ip);
        if (!active()) return;
        if (online) {
          setState(() {
            success = true;
            text = 'PC đã phản hồi. Sẵn sàng!';
          });
          try {
            await widget.onOnline();
          } catch (_) {
            /* Wake result remains valid. */
          }
          return;
        }
        setState(() => elapsed = watch.elapsed.inSeconds);
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted && active()) {
        setState(
          () => text = 'Đã gửi tín hiệu Wake-on-LAN nhưng chưa phát hiện PC hoạt động. Máy có thể chưa khởi động xong hoặc đang chặn kiểm tra kết nối.',
        );
      }
    } on StateError catch (e) {
      if (active()) setState(() => text = e.message.toString());
    } catch (_) {
      if (mounted && active()) {
        setState(
          () => text = 'Chưa gửi được tín hiệu. Kiểm tra Wi-Fi và quyền Mạng cục bộ trong Cài đặt rồi thử lại.',
        );
      }
    } finally {
      if (active()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.pc.name)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(32),
          children: [
            WakeOrb(success: success, busy: busy),
            const SizedBox(height: 32),
            Text(
              success
                  ? 'Xin chào, PC!'
                  : busy
                  ? 'Đánh thức máy tính'
                  : 'Kiểm tra máy tính',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.7, color: muted),
            ),
            const SizedBox(height: 24),
            if (busy) ...[
              LinearProgressIndicator(
                value: elapsed == 0
                    ? null
                    : (elapsed / widget.pc.timeout).clamp(0, 1),
              ),
              const SizedBox(height: 12),
              Text(
                '$elapsed / ${widget.pc.timeout} giây',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () {
                  generation++;
                  setState(() {
                    busy = false;
                    text =
                        'Đã dừng theo dõi. Tín hiệu đã gửi không thể thu hồi.';
                  });
                },
                child: const Text('Dừng theo dõi'),
              ),
            ],
            if (!busy) ...[
              FilledButton(
                onPressed: success ? () => Navigator.pop(context) : run,
                child: Text(success ? 'Hoàn tất' : 'Thử lại'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DiagnosticsPage(pc: widget.pc, net: widget.net),
                  ),
                ),
                child: const Text('Kiểm tra cấu hình'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class DiagnosticsPage extends StatelessWidget {
  final Pc pc;
  final NetworkService net;
  const DiagnosticsPage({super.key, required this.pc, required this.net});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kiểm tra cấu hình')),
    body: FutureBuilder<Lan?>(
      future: net.network(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final lan = snapshot.data;
        Widget row(bool ok, String title, String subtitle) => ListTile(
          leading: Icon(
            ok ? Icons.check_circle_outline : Icons.help_outline,
            color: ok ? green : Colors.orange.shade700,
          ),
          title: Text(title),
          subtitle: Text(subtitle),
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(pc.name, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            row(
              lan != null,
              'Kết nối Wi-Fi',
              lan == null
                  ? 'Kết nối cùng mạng với máy tính.'
                  : 'Đã nhận thông tin mạng.',
            ),
            row(
              lan != null && pc.ip.isNotEmpty && lan.contains(pc.ip),
              'PC cùng mạng',
              pc.ip.isEmpty ? 'Chưa có địa chỉ IP để kiểm tra.' : pc.ip,
            ),
            row(true, 'Địa chỉ MAC đã lưu', pc.mac),
            row(
              lan != null || pc.broadcast.isNotEmpty,
              'Địa chỉ gửi tín hiệu',
              pc.broadcast.isEmpty
                  ? lan?.broadcast ?? 'Chưa xác định'
                  : pc.broadcast,
            ),
            row(
              false,
              'Wake-on-LAN trong BIOS',
              'Cần xác nhận trực tiếp trên PC.',
            ),
            row(
              false,
              'Wake on Magic Packet trong Windows',
              'Cần xác nhận trực tiếp trên PC.',
            ),
            const SizedBox(height: 16),
            const HelpContent(embedded: true),
          ],
        );
      },
    ),
  );
}

class HelpContent extends StatelessWidget {
  final bool embedded;
  final String? notice;
  const HelpContent({super.key, this.embedded = false, this.notice});
  @override
  Widget build(BuildContext context) {
    const guides = {
      'Wake-on-LAN là gì?': 'Bật máy tính bằng tín hiệu gửi qua mạng nội bộ. PC cần còn cắm nguồn và card mạng hỗ trợ Wake-on-LAN. Bản này sử dụng Wi-Fi cùng mạng với PC, chưa hỗ trợ bật từ 4G/5G.',
      '1. Chuẩn bị BIOS / UEFI': 'Vào BIOS / UEFI của PC, tìm Wake on LAN, Power On by PCI-E hoặc Resume by LAN và bật. Tên mục khác nhau theo hãng và model. Chế độ ErP / Deep Sleep có thể ngắt nguồn card mạng khi tắt máy; kiểm tra hướng dẫn của nhà sản xuất.',
      '2. Thiết lập Windows': 'Mở Device Manager → Network adapters → card Ethernet → Properties. Trong Advanced, bật Wake on Magic Packet nếu có. Trong Power Management, cho phép thiết bị đánh thức máy và chỉ đánh thức bằng Magic Packet. Khả năng bật từ trạng thái tắt hoàn toàn phụ thuộc phần cứng và driver; hãy thử Sleep trước.',
      '3. Cách tìm MAC và IP': 'Trên PC Windows, mở Command Prompt và nhập ipconfig /all. Tìm card Ethernet đang cắm dây: Physical Address là MAC, IPv4 Address là IP. Nhập MAC theo dạng AA-BB-CC-DD-EE-FF hoặc AA:BB:CC:DD:EE:FF. Không dùng MAC của adapter VPN.',
      'Không tìm thấy PC khi quét?': 'Giữ PC đang bật, cùng mạng Wi-Fi/LAN và tránh Wi-Fi khách. Router không được bật Client Isolation. Bộ quét chỉ tìm thiết bị phản hồi trên cổng 445, 3389, 22 hoặc 80; firewall có thể chặn. Bạn luôn có thể thêm thủ công.',
      'Đã gửi tín hiệu nhưng máy chưa bật?': 'Kiểm tra PC còn cắm nguồn và dây LAN, BIOS và card mạng đã bật Wake-on-LAN. Kiểm tra đúng MAC Ethernet. Đã gửi tín hiệu không có nghĩa PC đã bật; app chỉ xác nhận khi nhận được phản hồi kết nối.',
      'Quyền mạng và quyền riêng tư': 'Trên iPhone, cho phép Mạng cục bộ khi hệ thống hỏi; nếu đã từ chối, bật lại trong Cài đặt → Quyền riêng tư & Bảo mật → Mạng cục bộ. Máy tính và lịch sử chỉ được lưu trên thiết bị. App không cần tài khoản.',
    };
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notice != null)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5E2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              notice!,
              style: const TextStyle(color: Color(0xFF805510), height: 1.6),
            ),
          ),
        if (!embedded) ...[
          const SectionTitle(
            'Luôn có lời giải',
            'Thiết lập một lần. Dùng mỗi ngày.',
          ),
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              children: [
                IconTile(
                  Icons.tips_and_updates_outlined,
                  background: Colors.white,
                  size: 46,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mới với Wake-on-LAN?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Bắt đầu với hướng dẫn bên dưới.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'HƯỚNG DẪN & GIẢI ĐÁP',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
        ],
        ...guides.entries.indexed.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Icon(
                  [
                    Icons.bolt_outlined,
                    Icons.memory_rounded,
                    Icons.window_rounded,
                    Icons.fingerprint_rounded,
                    Icons.wifi_find_rounded,
                    Icons.power_settings_new_rounded,
                    Icons.shield_outlined,
                  ][item.$1],
                  color: accent,
                  size: 21,
                ),
                title: Text(
                  item.$2.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    child: Text(
                      item.$2.value,
                      style: const TextStyle(
                        height: 1.7,
                        color: muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return embedded
        ? content
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            child: content,
          );
  }
}

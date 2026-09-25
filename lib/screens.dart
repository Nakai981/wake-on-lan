import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart';
import 'design.dart';
import 'models.dart';
import 'services.dart';
import 'setup.dart';

String stamp(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${date.day}/${date.month}';
void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class HomePage extends StatefulWidget {
  final DeviceStore store;
  final NetworkService net;
  const HomePage({super.key, required this.store, required this.net});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
  }

  @override
  void dispose() {
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
        setState(() => statuses[pc.id] = 'Đang kiểm tra…');
        final online =
            current != null &&
            pc.ip.isNotEmpty &&
            current.contains(pc.ip) &&
            await widget.net.reachable(pc.ip);
        if (!mounted) return;
        setState(
          () => statuses[pc.id] = online ? 'Đang hoạt động' : 'Chưa xác định',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          lan = null;
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

  Future<void> wake(Pc pc) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WakePage(
          pc: pc,
          net: widget.net,
          onSent: () async {
            await persist(
              pcs
                  .map(
                    (p) => p.id == pc.id ? p.copy(lastWake: DateTime.now()) : p,
                  )
                  .toList(),
            );
            await widget.store.log('Đã gửi tín hiệu · ${pc.name}');
          },
          onOnline: () => widget.store.log('Đã nhận phản hồi · ${pc.name}'),
        ),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> action(String value, Pc pc) async {
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
          await persist(pcs.where((p) => p.id != pc.id).toList());
        }
      }
    } catch (_) {
      if (mounted) message(context, 'Không lưu được thay đổi. Hãy thử lại.');
    }
  }

  bool favoritesOnly = false;

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
          tab = 0;
          favoritesOnly = false;
        });
      case 'history':
        setState(() => tab = 1);
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
                'Luôn xuất hiện đầu danh sách',
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

  @override
  Widget build(BuildContext context) {
    final sorted =
        pcs
            .where((p) => pcs.length < 2 || !favoritesOnly || p.favorite)
            .toList()
          ..sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 22,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: navy,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: mint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'wake',
                style: TextStyle(
                  fontSize: 25,
                  letterSpacing: -1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                ' my pc',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: IconButton.filledTonal(
              tooltip: 'Mở menu',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: navy,
              ),
              onPressed: openMenu,
              icon: const Icon(Icons.grid_view_rounded, size: 21),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: tab == 1
                  ? history()
                  : tab == 2
                  ? const HelpContent(key: ValueKey('help'))
                  : home(sorted),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE1E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x080F1238),
                  blurRadius: 24,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                height: 64,
                selectedIndex: tab,
                onDestinationSelected: (v) => setState(() => tab = v),
                backgroundColor: Colors.white,
                indicatorColor: soft,
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => TextStyle(
                    fontFamily: uiFont,
                    fontSize: 11,
                    fontWeight: states.contains(WidgetState.selected)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: states.contains(WidgetState.selected)
                        ? accent
                        : muted,
                  ),
                ),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined, size: 22),
                    selectedIcon: Icon(
                      Icons.space_dashboard_rounded,
                      color: accent,
                      size: 22,
                    ),
                    label: 'Máy tính',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.access_time_rounded, size: 22),
                    selectedIcon: Icon(
                      Icons.history_rounded,
                      color: accent,
                      size: 22,
                    ),
                    label: 'Hoạt động',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_stories_outlined, size: 22),
                    selectedIcon: Icon(
                      Icons.auto_stories_rounded,
                      color: accent,
                      size: 22,
                    ),
                    label: 'Trợ giúp',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget filterChip(String label, bool favorite) => ChoiceChip(
    label: Text(label),
    selected: favoritesOnly == favorite,
    showCheckmark: false,
    selectedColor: navy,
    backgroundColor: Colors.white,
    side: BorderSide.none,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: favoritesOnly == favorite ? Colors.white : muted,
    ),
    onSelected: (_) => setState(() => favoritesOnly = favorite),
  );

  Widget networkBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE1E8F0)),
    ),
    child: Row(
      children: [
        IconTile(
          lan == null ? Icons.wifi_off_rounded : Icons.wifi_rounded,
          size: 34,
          background: lan == null
              ? const Color(0xFFFFF5E2)
              : const Color(0xFFE5F6F0),
          color: lan == null
              ? const Color(0xFF9B6813)
              : const Color(0xFF138268),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            refreshing
                ? 'Đang kiểm tra kết nối…'
                : lan != null
                ? 'Đã kết nối mạng Wi-Fi'
                : 'Kết nối Wi-Fi cùng mạng với PC',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Kiểm tra lại',
          onPressed: refreshing ? null : refresh,
          icon: const Icon(Icons.refresh_rounded, size: 19, color: muted),
        ),
      ],
    ),
  );

  Widget home(List<Pc> sorted) => RefreshIndicator(
    onRefresh: refresh,
    child: ListView(
      key: const ValueKey('devices'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Máy tính của bạn',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: 23),
              ),
            ),
            if (pcs.isNotEmpty)
              IconButton(
                tooltip: 'Thêm máy tính',
                onPressed: storageError ? null : () => edit(),
                icon: const Icon(Icons.add_rounded, color: accent),
              ),
          ],
        ),
        const SizedBox(height: 12),
        networkBar(),
        const SizedBox(height: 16),
        if (storageError)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Không đọc được dữ liệu đã lưu. Hãy khởi động lại app; dữ liệu gốc chưa bị thay đổi.',
            ),
          ),
        if (pcs.isEmpty)
          empty()
        else ...[
          if (pcs.length > 1) ...[
            Wrap(
              spacing: 8,
              children: [
                filterChip('Tất cả', false),
                filterChip('Yêu thích', true),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (sorted.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chưa có máy yêu thích.',
                      style: TextStyle(color: muted),
                    ),
                    TextButton(
                      onPressed: () => setState(() => favoritesOnly = false),
                      child: const Text('Xem tất cả máy'),
                    ),
                  ],
                ),
              ),
            ),
          ...sorted.map(
            (pc) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: deviceCard(pc),
            ),
          ),
        ],
      ],
    ),
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
              onPressed: () => wake(pc),
              style: FilledButton.styleFrom(
                backgroundColor: mint,
                foregroundColor: navy,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.power_settings_new_rounded, size: 20),
              label: const Text(
                'BẬT PC',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ),
          ),
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
  const HelpContent({super.key, this.embedded = false});
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

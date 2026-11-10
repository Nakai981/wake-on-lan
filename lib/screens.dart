import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'models.dart';
import 'services.dart';
import 'setup.dart';
import 'agent_client.dart';
import 'agent_pair.dart';
import 'remote_control.dart';
import 'app_theme.dart';
import 'power_confirmation_effect.dart';
import 'wake_console.dart';
import 'power_delay.dart';
import 'power_delay_settings.dart';
import 'help.dart';
import 'workspace.dart';

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
  AgentClient get agent => widget.agentClient ?? AgentClient();
  final Set<String> powerBusy = {};
  final Set<String> onlineIds = {};
  final Set<String> manuallyOnline = {};
  final Set<String> manuallyOffline = {};
  int confirmationEffect = 0;
  Timer? statusTimer;
  final Map<String, WakeSession> wakeSessions = {};
  final Map<String, Timer> powerTimers = {};
  final Set<String> cancelledPower = {};
  bool get supportsSiri =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  int siriActivityVersion = 0;
  bool reloadingStore = false;
  bool showSiriGuide = false;

  Future<bool> pcReachable(Pc pc) async {
    if (!pc.agentPaired) return widget.net.reachable(pc.ip);
    try {
      return await agent.command(pc, 'status') == 'online';
    } catch (_) {
      return false;
    }
  }

  Future<void> pairAgent(Pc pc) async {
    final paired = await Navigator.push<Pc>(
      context,
      MaterialPageRoute(
        builder: (_) => AgentPairPage(pc: pc, agentClient: agent),
      ),
    );
    if (!mounted || paired == null) return;
    try {
      await persist(
        pcs
            .map(
              (p) =>
                  p.id == pc.id ? p.copy(agentPaired: true, ip: paired.ip) : p,
            )
            .toList(),
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

  Future<String> power(Pc pc, String command) async {
    if (powerBusy.contains(pc.id) || waking.contains(pc.id)) {
      return 'A command for this PC is already in progress.';
    }
    if (!pc.agentPaired) {
      await pairAgent(pc);
      if (!mounted) return 'The request was cancelled.';
      final saved = pcs.where((p) => p.id == pc.id);
      if (saved.isEmpty || !saved.first.agentPaired) {
        return 'Pair this PC with Windows Agent first.';
      }
      pc = saved.first;
    }
    if (!mounted) return 'The request was cancelled.';
    final label = command == 'sleep' ? 'Sleep' : 'Tắt máy';
    final delay = widget.store.powerDelaySeconds;
    final delayLabel = powerDelayLabel(delay);
    final checkDelay = delay + 10;
    final checkLabel = powerDelayLabel(checkDelay);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$label ${pc.name}?'),
            content: Text(
              command == 'shutdown'
                  ? 'Lưu công việc trên PC trước khi tắt. Windows Agent sẽ chờ $delayLabel để bạn có thể hủy.'
                  : 'PC sẽ chuyển sang Sleep sau $delayLabel. Bạn có thể bật lại bằng Wake-on-LAN nếu đã cấu hình.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(label),
              ),
            ],
          ),
        ) ==
        true;
    if (!mounted || !confirmed) return 'The request was cancelled.';
    if (powerBusy.contains(pc.id) || waking.contains(pc.id)) {
      return 'A command for this PC is already in progress.';
    }
    setState(() => powerBusy.add(pc.id));
    try {
      final result = await agent.command(pc, powerDelayCommand(command, delay));
      if (!mounted) {
        return 'The request may have reached your PC. Check your PC before trying again.';
      }
      if (result != 'accepted') {
        message(
          context,
          result == 'busy'
              ? 'PC đang có một lệnh chờ. Hủy lệnh trước khi gửi lại.'
              : 'Agent chưa nhận lệnh.',
        );
        return result == 'busy'
            ? 'Your PC already has a pending power command. Cancel it before sending another.'
            : result == 'simulated'
            ? 'Windows Agent is in simulation mode. No power action was scheduled.'
            : 'Windows Agent did not accept the command. Check or update Windows Agent.';
      }
      setState(() {
        cancelledPower.remove(pc.id);
        statuses[pc.id] = 'Đã gửi $label · thực hiện sau $delayLabel';
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: Duration(seconds: delay.clamp(1, 10)),
            content: Text(
              'PC đã nhận lệnh $label, sẽ thực hiện sau $delayLabel.',
            ),
            action: SnackBarAction(
              label: 'Hủy lệnh',
              onPressed: () => cancelPower(pc),
            ),
          ),
        );
      try {
        await widget.store.log(
          'Đã gửi lệnh $label · ${pc.name} · chờ $delayLabel',
        );
      } catch (_) {}
      powerTimers[pc.id]?.cancel();
      powerTimers[pc.id] = Timer(Duration(seconds: checkDelay), () async {
        final online = await pcReachable(pc);
        if (!mounted || cancelledPower.contains(pc.id)) return;
        setState(() {
          powerBusy.remove(pc.id);
          manuallyOnline.remove(pc.id);
          manuallyOffline.remove(pc.id);
          if (online) {
            onlineIds.add(pc.id);
          } else {
            onlineIds.remove(pc.id);
          }
          statuses[pc.id] = online ? 'Đang hoạt động' : 'Chưa xác định';
        });
        powerTimers.remove(pc.id);
        message(
          context,
          online
              ? 'PC vẫn phản hồi sau $checkLabel.'
              : 'PC chưa phản hồi sau $checkLabel; chưa xác nhận chắc chắn đã Sleep/tắt.',
        );
      });
      return command == 'sleep'
          ? 'Your PC accepted the sleep command. It is scheduled in $delay seconds.'
          : 'Your PC accepted the shutdown command. It is scheduled in $delay seconds.';
    } catch (_) {
      if (mounted) {
        message(
          context,
          delay == defaultPowerDelay
              ? 'Chưa xác nhận được lệnh. Kiểm tra Agent, IP và mã ghép nối. Nếu mất kết nối sau khi gửi, hãy kiểm tra hoặc hủy trên PC.'
              : 'Chưa xác nhận được lệnh. Cập nhật Windows Agent để dùng thời gian chờ tùy chỉnh, kiểm tra IP và kết nối. Kiểm tra hoặc hủy trên PC nếu lệnh đã được gửi.',
        );
      }
      return 'The command could not be confirmed. It may have reached your PC. Check Windows Agent before trying again.';
    } finally {
      if (mounted && !powerTimers.containsKey(pc.id)) {
        setState(() => powerBusy.remove(pc.id));
      }
    }
  }

  Future<String> cancelPower(Pc pc) async {
    if (!mounted) return 'The request was cancelled.';
    try {
      final result = await agent.command(pc, 'cancel');
      if (result == 'cancelled') {
        cancelledPower.add(pc.id);
        powerTimers.remove(pc.id)?.cancel();
        if (mounted) setState(() => powerBusy.remove(pc.id));
      }
      if (mounted) {
        message(
          context,
          result == 'cancelled'
              ? 'Đã hủy lệnh còn đang chờ trên PC.'
              : 'Chưa hủy được lệnh.',
        );
      }
      if (mounted) refresh();
      return result == 'cancelled'
          ? 'The pending power command was cancelled.'
          : 'No cancellation was confirmed. Check Windows Agent on your PC.';
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Không liên lạc được với Agent để hủy. Lệnh có thể đã thực hiện.',
        );
      }
      return 'Windows Agent could not be reached. The power command may already have run.';
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
    siriActivityVersion = widget.store.siriActivityVersion;
    refresh();
    statusTimer = Timer.periodic(Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        refresh();
      }
    });
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    for (final timer in powerTimers.values) {
      timer.cancel();
    }
    for (final session in wakeSessions.values) {
      session.stopped = true;
    }
    for (final timer in wakeTimers.values) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(reloadAfterResume());
  }

  Future<void> reloadAfterResume() async {
    if (reloadingStore) return;
    reloadingStore = true;
    try {
      await widget.store.reload();
      final latest = widget.store.read();
      if (!mounted) return;
      setState(() {
        pcs = latest;
        storageError = false;
        if (siriActivityVersion != widget.store.siriActivityVersion) {
          final id = widget.store.siriActivityPcId;
          manuallyOnline.remove(id);
          manuallyOffline.remove(id);
          siriActivityVersion = widget.store.siriActivityVersion;
        }
      });
    } catch (_) {
      if (mounted) setState(() => storageError = true);
    } finally {
      reloadingStore = false;
    }
    if (mounted) await refresh();
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
        if (waking.contains(pc.id) ||
            powerBusy.contains(pc.id) ||
            manuallyOffline.contains(pc.id) ||
            manuallyOnline.contains(pc.id)) {
          continue;
        }
        setState(() => statuses[pc.id] = 'Đang kiểm tra…');
        final online =
            current != null &&
            pc.ip.isNotEmpty &&
            current.contains(pc.ip) &&
            await pcReachable(pc);
        if (!mounted) return;
        setState(() {
          if (!waking.contains(pc.id) &&
              !powerBusy.contains(pc.id) &&
              !manuallyOffline.contains(pc.id) &&
              !manuallyOnline.contains(pc.id)) {
            statuses[pc.id] = online ? 'Đang hoạt động' : 'Chưa xác định';
            if (online) {
              manuallyOnline.remove(pc.id);
              onlineIds.add(pc.id);
            } else if (!manuallyOnline.contains(pc.id)) {
              onlineIds.remove(pc.id);
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          lan = null;
          onlineIds.removeWhere((id) => !manuallyOnline.contains(id));
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
        builder: (_) =>
            SetupPage(net: widget.net, existing: pc, agentClient: agent),
      ),
    );
    if (result == null || !mounted) return;
    if (pcs.any((p) => p.mac == result.mac && p.id != result.id)) {
      message(context, 'Máy có địa chỉ MAC này đã được lưu.');
      return;
    }
    try {
      await persist([...pcs.where((p) => p.id != result.id), result]);
      manuallyOffline.remove(result.id);
      manuallyOnline.remove(result.id);
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

  void stopWake(Pc pc) {
    wakeTimers.remove(pc.id)?.cancel();
    final session = wakeSessions[pc.id];
    if (session != null) session.stopped = true;
    if (mounted) setState(() => waking.remove(pc.id));
  }

  void manualWake(Pc pc) {
    stopWake(pc);
    wakeSessions[pc.id]?.online = true;
    setState(() {
      manuallyOffline.remove(pc.id);
      manuallyOnline.add(pc.id);
      onlineIds.add(pc.id);
      statuses[pc.id] = 'Đã bật · bạn đã xác nhận';
      confirmationEffect++;
    });
    wakeSessions[pc.id]?.update('Đã bật · xác nhận thủ công');
    wakeSessions[pc.id]?.log(
      'Người dùng xác nhận PC đã bật. Không gửi thêm gói UDP.',
    );
  }

  void wakeNotStarted(Pc pc, {bool closeConsole = false}) {
    stopWake(pc);
    if (closeConsole) Navigator.pop(context);
    setState(() {
      manuallyOnline.remove(pc.id);
      manuallyOffline.add(pc.id);
      onlineIds.remove(pc.id);
      statuses[pc.id] = 'Chưa bật · xác nhận thủ công';
      wakeHelp =
          '${pc.name}: bạn xác nhận PC chưa được bật. Kiểm tra nguồn, Ethernet, MAC, BIOS và Windows theo hướng dẫn bên dưới.';
      showSiriGuide = false;
      tab = 2;
    });
  }

  Future<String> wake(Pc pc) async {
    if (waking.contains(pc.id) || powerBusy.contains(pc.id)) {
      return 'A command for this PC is already in progress.';
    }
    final session = WakeSession(pc);
    wakeSessions[pc.id] = session;
    setState(() {
      waking.add(pc.id);
      statuses[pc.id] = 'Đang gửi tín hiệu…';
    });
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => WakeConsolePage(
            session: session,
            confirmed: () => manualWake(pc),
            help: () => wakeNotStarted(pc, closeConsole: true),
          ),
        ),
      ),
    );
    try {
      session.log('Đọc Wi-Fi của điện thoại…');
      final current = await widget.net.network();
      if (!mounted || session.stopped) return 'The wake request was cancelled.';
      if (current == null) {
        throw StateError('Kết nối Wi-Fi cùng mạng với PC để bật máy.');
      }
      if (pc.network.isNotEmpty && pc.network != current.key) {
        throw StateError(
          'Subnet đã thay đổi. Sửa máy hoặc quét lại trước khi Wake.',
        );
      }
      session.log(
        'Wi-Fi ${current.ip} / ${current.mask} · broadcast ${current.broadcast}',
      );
      session.log(
        'Yêu cầu UDP ${pc.broadcast.isEmpty ? current.broadcast : pc.broadcast}:${pc.port} · MAC ${pc.mac} · ${pc.retries} lần',
      );
      await widget.net.wakeWithLog(pc, current, session.log);
      if (!mounted || session.stopped) {
        return 'The wake signal was sent. Your PC has not been confirmed online.';
      }
      session.sent = true;
      session.readyAt = DateTime.now().add(Duration(seconds: pc.startupDelay));
      session.update('Đã gửi · Chờ PC khởi động');
      session.log(
        'Đã gửi tín hiệu. Kiểm tra ngay và mỗi 3 giây; phản hồi sớm sẽ chuyển ngay. UDP không xác nhận PC đã nhận gói.',
      );
      setState(() => statuses[pc.id] = 'Chờ PC khởi động');
      notifyWake('Đã gửi tín hiệu khởi động đến ${pc.name}.');
      unawaited(checkWake(pc, current));
      try {
        await persist(
          pcs
              .map((p) => p.id == pc.id ? p.copy(lastWake: DateTime.now()) : p)
              .toList(),
        );
        await widget.store.log('Đã gửi Wake · ${pc.name}');
      } catch (_) {
        /* UDP succeeded even when local history could not be saved. */
      }
      return 'The wake signal was sent to your PC. This does not confirm that it is online yet.';
    } catch (e) {
      if (!mounted || session.stopped) return 'The wake request was cancelled.';
      session.log('Lỗi: $e');
      session.update('Chưa xác nhận gửi thành công');
      session.stopped = true;
      setState(() {
        waking.remove(pc.id);
        statuses[pc.id] = 'Chưa gửi được tín hiệu';
      });
      return 'The wake signal could not be confirmed. Check Wi-Fi, Local Network permission and this PC\'s settings in Wake My PC.';
    }
  }

  Future<void> checkWake(Pc pc, Lan sentNetwork) async {
    final session = wakeSessions[pc.id];
    if (!mounted ||
        session == null ||
        session.stopped ||
        !pcs.any((p) => p.id == pc.id)) {
      return;
    }
    var online = false;
    try {
      final current = await widget.net.network();
      if (current != null &&
          current.key == sentNetwork.key &&
          pc.ip.isNotEmpty &&
          current.contains(pc.ip)) {
        online = await pcReachable(pc)
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
      }
    } catch (e) {
      session.log('Kiểm tra trạng thái: $e');
    }
    if (!mounted || session.stopped || wakeSessions[pc.id] != session) return;
    if (online) {
      session.online = true;
      session.stopped = true;
      session.log('PC phản hồi tại ${pc.ip}.');
      session.update('PC đang phản hồi');
      setState(() {
        waking.remove(pc.id);
        manuallyOffline.remove(pc.id);
        manuallyOnline.remove(pc.id);
        onlineIds.add(pc.id);
        statuses[pc.id] = 'Đang hoạt động';
        confirmationEffect++;
      });
      wakeTimers.remove(pc.id)?.cancel();
      notifyWake('${pc.name} đang phản hồi.');
      return;
    }
    final elapsed = DateTime.now().isAfter(session.readyAt!);
    session.update(elapsed ? 'Chưa nhận phản hồi từ PC' : 'Chờ PC khởi động');
    session.log(
      pc.ip.isEmpty
          ? 'Chưa lưu IP để kiểm tra trạng thái.'
          : 'Chưa nhận phản hồi từ ${pc.ip}.',
    );
    if (elapsed) setState(() => statuses[pc.id] = 'Đang chờ phản hồi từ PC');
    final deadline = session.readyAt!.add(Duration(seconds: pc.timeout));
    if (DateTime.now().isAfter(deadline)) {
      session.log('Hết thời gian theo dõi. Không khẳng định PC đã tắt.');
      stopWake(pc);
      session.update('Chưa nhận phản hồi · Hết thời gian theo dõi');
      return;
    }
    wakeTimers[pc.id] = Timer(
      const Duration(seconds: 3),
      () => checkWake(pc, sentNetwork),
    );
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
            content: Text('Thông tin bật máy sẽ bị xóa khỏi điện thoại.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Xóa'),
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

  Future<void> openControls() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RemoteControlPage(
        pcName: selectedPc?.name,
        pc: selectedPc,
        agent: agent,
      ),
    ),
  );

  Future<void> openMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => WorkspaceSheet(
        powerDelay: powerDelayLabel(widget.store.powerDelaySeconds),
        deviceCount: pcs.length,
        canAddDevice: !storageError,
        showSiri: supportsSiri,
        onSelect: (value) => Navigator.pop(ctx, value),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'powerDelay':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PowerDelaySettings(store: widget.store),
        );
        if (mounted && saved == true) {
          message(
            context,
            'Đã lưu thời gian chờ ${powerDelayLabel(widget.store.powerDelaySeconds)} cho Shutdown và Sleep.',
          );
        }
      case 'controls':
        await openControls();
      case 'siriHelp':
        setState(() {
          showSiriGuide = true;
          tab = 2;
        });
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
              appBar: AppBar(title: Text('Lịch sử hoạt động')),
              body: history(),
            ),
          ),
        );
      case 'help':
        setState(() {
          showSiriGuide = false;
          tab = 2;
        });
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
    padding: EdgeInsets.only(bottom: 8),
    child: ListTile(
      enabled: enabled,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
      leading: IconTile(icon, size: 42),
      title: Text(
        title,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 20,
      ),
      onTap: () => Navigator.pop(ctx, id),
    ),
  );

  Future<void> deviceMenu(Pc pc) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(Icons.desktop_windows_rounded),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      pc.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
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
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFCE3956),
                ),
                title: Text(
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = Theme.of(context).colorScheme.onSurface;
    final background = Theme.of(context).colorScheme.surface;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                systemNavigationBarColor: background,
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
          const AppearanceSwitch(),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Kiểm tra lại',
            onPressed: refreshing ? null : refresh,
            icon: Icon(
              Icons.refresh_rounded,
              color: dark
                  ? Colors.white60
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: 'Mở menu',
            onPressed: openMenu,
            icon: Icon(Icons.more_horiz_rounded, color: foreground),
          ),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 650),
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: tab == 1
                      ? deviceList()
                      : tab == 2
                      ? HelpContent(
                          key: ValueKey('help-$showSiriGuide'),
                          openSiri: showSiriGuide,
                          notice: wakeHelp,
                        )
                      : controlHome(pc, online),
                ),
              ),
            ),
            if (tab == 0 && online && confirmationEffect > 0)
              PowerConfirmationEffect(
                key: ValueKey(confirmationEffect),
                onEnd: () {
                  if (mounted) setState(() => confirmationEffect = 0);
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.primaryContainer,
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() {
          tab = value;
          if (value == 2) showSiriGuide = false;
          confirmationEffect = 0;
        }),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: uiFont,
            fontSize: 11,
            color: dark
                ? (states.contains(WidgetState.selected)
                      ? Colors.white
                      : Colors.white54)
                : (states.contains(WidgetState.selected)
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.power_settings_new_rounded,
              color: dark
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: dark
                  ? Colors.white54
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            selectedIcon: Icon(
              Icons.dns_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: 'Danh sách',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.help_outline_rounded,
              color: dark
                  ? Colors.white54
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            selectedIcon: Icon(
              Icons.help_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: 'Trợ giúp',
          ),
        ],
      ),
    );
  }

  Widget controlHome(Pc? pc, bool online) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final busy =
        pc != null && (waking.contains(pc.id) || powerBusy.contains(pc.id));
    return LayoutBuilder(
      key: ValueKey('home-${pc?.id}-$online'),
      builder: (context, constraints) => SingleChildScrollView(
        key: ValueKey('control-${pc?.id}-$online'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (pc == null) ...[
                  Icon(
                    Icons.star_outline_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 44,
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Chọn một máy cho Home',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    storageError
                        ? 'Không đọc được dữ liệu đã lưu. Hãy khởi động lại app.'
                        : 'Đánh dấu sao một máy trong Danh sách\nđể điều khiển ngay tại đây.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary, height: 1.7),
                  ),
                  SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: () => setState(() => tab = 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text('Chọn máy tính'),
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
                  SizedBox(height: 10),
                  Text(
                    online
                        ? manuallyOnline.contains(pc.id)
                              ? 'Đã bật · bạn đã xác nhận'
                              : 'Đang hoạt động'
                        : waking.contains(pc.id)
                        ? (statuses[pc.id] ?? 'Đang gửi tín hiệu…')
                        : refreshing
                        ? 'Đang kiểm tra…'
                        : manuallyOffline.contains(pc.id)
                        ? 'Chưa bật · xác nhận thủ công'
                        : 'Chưa nhận được phản hồi',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Tooltip(
                    message:
                        'Chỉ đổi trạng thái trong app, không gửi lệnh đến PC',
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              if (!online) HapticFeedback.lightImpact();
                              setState(() {
                                if (online) {
                                  manuallyOnline.remove(pc.id);
                                  manuallyOffline.add(pc.id);
                                  onlineIds.remove(pc.id);
                                } else {
                                  confirmationEffect++;
                                  manuallyOffline.remove(pc.id);
                                  manuallyOnline.add(pc.id);
                                  onlineIds.add(pc.id);
                                }
                                statuses[pc.id] = online
                                    ? 'Chưa bật · xác nhận thủ công'
                                    : 'Đã bật · bạn đã xác nhận';
                              });
                            },
                      icon: Icon(
                        online
                            ? Icons.toggle_on_rounded
                            : Icons.toggle_off_outlined,
                      ),
                      label: Text(
                        online ? 'Đánh dấu PC đã tắt' : 'Đánh dấu PC đã bật',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: secondary,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 28),
                  if (!online) ...[
                    AnimatedContainer(
                      duration: Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: busy
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (busy
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white)
                                    .withValues(alpha: .12),
                            blurRadius: busy ? 56 : 32,
                            spreadRadius: busy ? 8 : 0,
                          ),
                        ],
                      ),
                      width: 152,
                      height: 152,
                      child: FilledButton(
                        onPressed: busy ? null : () => wake(pc),
                        style: FilledButton.styleFrom(
                          shape: CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onPrimary,
                          disabledBackgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          disabledForegroundColor: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: 350),
                          child: Icon(
                            busy
                                ? Icons.wifi_tethering_rounded
                                : Icons.power_settings_new_rounded,
                            key: ValueKey(busy),
                            size: 54,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 22),
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
                        SizedBox(width: 16),
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
                      SizedBox(height: 18),
                      Text(
                        'Ghép nối Windows Agent để dùng Sleep và Shutdown.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      TextButton(
                        onPressed: () => pairAgent(pc),
                        child: Text('Ghép nối Agent'),
                      ),
                    ],
                  ],
                  SizedBox(height: 36),
                  if (online)
                    TextButton.icon(
                      onPressed: openControls,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      icon: Icon(Icons.touch_app_outlined, size: 19),
                      label: Text('Điều khiển · Xem trước'),
                    ),
                  TextButton(
                    onPressed: () => setState(() => tab = 1),
                    style: TextButton.styleFrom(foregroundColor: secondary),
                    child: Text('Đổi máy tính', style: TextStyle(fontSize: 12)),
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
      onPressed: busy ? null : () => power(pc, command),
      style: FilledButton.styleFrom(
        backgroundColor: command == 'sleep'
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : Theme.of(context).colorScheme.primary,
        foregroundColor: command == 'sleep'
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34),
          SizedBox(height: 18),
          Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  Widget deviceList() => ListView(
    key: ValueKey('devices'),
    padding: EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Một dấu sao. Một máy trên Home.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Thêm máy tính',
            onPressed: storageError ? null : () => edit(),
            icon: Icon(
              Icons.add_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      SizedBox(height: 16),
      if (pcs.isEmpty) empty(),
      ...pcs.map(
        (pc) => Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: EdgeInsets.fromLTRB(10, 12, 8, 12),
              leading: IconButton(
                tooltip: pc.favorite
                    ? 'Máy đang hiển thị trên Home'
                    : 'Chọn ${pc.name} cho Home',
                onPressed: () => action('favorite', pc),
                icon: Icon(
                  pc.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: pc.favorite
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              title: Text(
                pc.name,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                statuses[pc.id] ?? 'Chưa xác định',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                tooltip: 'Tùy chọn máy',
                onPressed: () => deviceMenu(pc),
                icon: Icon(Icons.more_horiz_rounded),
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
      color: Theme.of(context).colorScheme.onSurface,
      gradient: panelGradient,
      borderRadius: BorderRadius.circular(24),
    ),
    padding: EdgeInsets.all(22),
    child: Column(
      children: [
        IconTile(
          Icons.desktop_windows_rounded,
          color: mint,
          background: Color(0xFF20354D),
          size: 58,
        ),
        SizedBox(height: 18),
        Text(
          'PC của bạn, trong tầm tay',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Thêm PC để bật máy chỉ với một chạm.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB4C5D9), fontSize: 12, height: 1.6),
        ),
        SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: storageError ? null : () => edit(),
            style: FilledButton.styleFrom(
              backgroundColor: mint,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: Size(48, 50),
            ),
            icon: Icon(Icons.add_rounded, size: 20),
            label: Text('Bắt đầu thiết lập'),
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
        color: Theme.of(context).colorScheme.onSurface,
        gradient: panelGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                Icons.desktop_windows_rounded,
                color: Color(0xFF7DD3FC),
                background: Color(0xFF20354D),
                size: 42,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pc.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 5,
                          color: online ? mint : Color(0xFFF4C76B),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statuses[pc.id] ?? 'Chưa xác định',
                            style: TextStyle(
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
                Tooltip(
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
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: Color(0xFFB4C5D9),
                  size: 22,
                ),
              ),
            ],
          ),
          if (changed)
            Padding(
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
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: waking.contains(pc.id) || powerBusy.contains(pc.id)
                  ? null
                  : () => wake(pc),
              style: FilledButton.styleFrom(
                backgroundColor: mint,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                minimumSize: Size(48, 48),
              ),
              icon: Icon(Icons.power_settings_new_rounded, size: 20),
              label: Text(
                waking.contains(pc.id) ? 'ĐANG XỬ LÝ…' : 'BẬT PC',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ),
          ),
          if (pc.agentPaired) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        waking.contains(pc.id) || powerBusy.contains(pc.id)
                        ? null
                        : () => power(pc, 'sleep'),
                    icon: Icon(Icons.bedtime_outlined, size: 17),
                    label: Text('Sleep'),
                    style: TextButton.styleFrom(
                      foregroundColor: Color(0xFFB4C5D9),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed:
                        waking.contains(pc.id) || powerBusy.contains(pc.id)
                        ? null
                        : () => power(pc, 'shutdown'),
                    icon: Icon(Icons.power_settings_new, size: 17),
                    label: Text('Tắt máy'),
                    style: TextButton.styleFrom(
                      foregroundColor: Color(0xFFFDA4AF),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (pc.lastWake != null) ...[
            SizedBox(height: 10),
            Text(
              'Gửi gần nhất: ${stamp(pc.lastWake!)}',
              style: TextStyle(fontSize: 10, color: Color(0xFF9CAFC6)),
            ),
          ],
        ],
      ),
    );
  }

  Widget history() {
    final entries = widget.store.history();
    return ListView(
      key: ValueKey('history'),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24),
      children: [
        SectionTitle('Hoạt động gần đây', 'Mỗi lần kết nối, đều được ghi nhớ.'),
        if (entries.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                children: [
                  IconTile(Icons.history_rounded, size: 64),
                  SizedBox(height: 20),
                  Text(
                    'Một khởi đầu mới',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Lịch sử sẽ xuất hiện tại đây\nsau khi bạn gửi tín hiệu bật PC.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.7,
                    ),
                  ),
                  SizedBox(height: 22),
                  TextButton(
                    onPressed: () => setState(() => tab = 0),
                    child: Text('Về máy tính của tôi'),
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
            padding: EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: IconTile(Icons.bolt_rounded, size: 40),
                title: Text(
                  split < 0 ? entry : entry.substring(split + 1),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Text(
                    date == null ? '' : stamp(date),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
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
        await Future<void>.delayed(Duration(seconds: 2));
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
        constraints: BoxConstraints(maxWidth: 550),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.all(32),
          children: [
            WakeOrb(success: success, busy: busy),
            SizedBox(height: 32),
            Text(
              success
                  ? 'Xin chào, PC!'
                  : busy
                  ? 'Đánh thức máy tính'
                  : 'Kiểm tra máy tính',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.7,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 24),
            if (busy) ...[
              LinearProgressIndicator(
                value: elapsed == 0
                    ? null
                    : (elapsed / widget.pc.timeout).clamp(0, 1),
              ),
              SizedBox(height: 12),
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
                child: Text('Dừng theo dõi'),
              ),
            ],
            if (!busy) ...[
              FilledButton(
                onPressed: success ? () => Navigator.pop(context) : run,
                child: Text(success ? 'Hoàn tất' : 'Thử lại'),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DiagnosticsPage(pc: widget.pc, net: widget.net),
                  ),
                ),
                child: Text('Kiểm tra cấu hình'),
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
    appBar: AppBar(title: Text('Kiểm tra cấu hình')),
    body: FutureBuilder<Lan?>(
      future: net.network(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator());
        }
        final lan = snapshot.data;
        Widget row(bool ok, String title, String subtitle) => ListTile(
          leading: Icon(
            ok ? Icons.check_circle_outline : Icons.help_outline,
            color: ok
                ? Theme.of(context).colorScheme.primary
                : Colors.orange.shade700,
          ),
          title: Text(title),
          subtitle: Text(subtitle),
        );
        return ListView(
          padding: EdgeInsets.all(20),
          children: [
            Text(pc.name, style: Theme.of(context).textTheme.headlineMedium),
            SizedBox(height: 16),
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
            SizedBox(height: 16),
            const HelpContent(embedded: true),
          ],
        );
      },
    ),
  );
}

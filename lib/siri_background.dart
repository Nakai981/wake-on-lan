import 'agent_client.dart';
import 'models.dart';
import 'power_delay.dart';
import 'services.dart';
import 'siri_shortcuts.dart';

/// One short-lived Siri execution session. No widgets, navigation or UI timers.
/// The native caller gathers power confirmation before consuming a ticket.
class SiriBackgroundSession {
  final DeviceStore store;
  final NetworkService network;
  final AgentClient agent;
  late final SiriShortcuts shortcuts;
  bool _busy = false;

  SiriBackgroundSession({
    required this.store,
    required this.network,
    required this.agent,
  }) {
    shortcuts = SiriShortcuts(
      store: store,
      network: network,
      agent: agent,
      devices: store.read,
      isBusy: (_) => _busy,
      execute: _execute,
      refresh: store.reload,
    );
  }

  Future<String> _execute(String action, Pc pc, int delay) async {
    if (_busy) return 'A command for this PC is already in progress.';
    _busy = true;
    try {
      if (action == 'wake') {
        final lan = await network.network();
        if (lan == null ||
            (pc.network.isNotEmpty && pc.network != lan.key) ||
            (pc.broadcast.isNotEmpty && !lan.contains(pc.broadcast))) {
          return 'The network changed. Connect to the same Wi-Fi as your PC and ask Siri again.';
        }
        // No retries beyond the PC's explicitly saved Magic Packet count.
        await network.wake(pc, lan);
        await _record(pc, action, 'Đã gửi Wake');
        return 'The wake signal was sent. This does not confirm that your PC is online yet.';
      }
      final command = action == 'cancel'
          ? 'cancel'
          : powerDelayCommand(action, delay);
      final result = await agent.command(pc, command);
      if (action == 'cancel') {
        if (result != 'cancelled') {
          return 'No cancellation was confirmed. Check Windows Agent on your PC.';
        }
        await _record(pc, action, 'Đã hủy lệnh nguồn đang chờ');
        return 'The pending power command was cancelled.';
      }
      if (result == 'busy') {
        return 'Your PC already has a pending power command. Cancel it before sending another.';
      }
      if (result == 'simulated') {
        return 'Windows Agent is in simulation mode. No power action was scheduled.';
      }
      if (result != 'accepted') {
        return 'Windows Agent did not accept the command. Check or update Windows Agent.';
      }
      await _record(
        pc,
        action,
        'Đã gửi ${action == 'sleep' ? 'Sleep' : 'Shutdown'} · chờ ${powerDelayLabel(delay)}',
      );
      return action == 'sleep'
          ? 'Your PC accepted the sleep command. It is scheduled in $delay seconds.'
          : 'Your PC accepted the shutdown command. It is scheduled in $delay seconds.';
    } catch (_) {
      return action == 'wake'
          ? 'The wake signal could not be confirmed. Open Wake My PC to check Wi-Fi and Local Network permission.'
          : 'The command could not be confirmed. It may have reached your PC. Check Windows Agent before trying again.';
    } finally {
      _busy = false;
    }
  }

  Future<void> _record(Pc pc, String action, String description) async {
    try {
      await store.reload();
      if (action == 'wake') {
        final current = store.read();
        await store.save(
          current
              .map(
                (p) => p.id == pc.id && p.mac == pc.mac
                    ? p.copy(lastWake: DateTime.now())
                    : p,
              )
              .toList(),
        );
      }
      await store.log('Siri · $description · ${pc.name}');
      await store.markSiriActivity(pc.id);
    } catch (_) {
      // A local persistence failure must never cause a second network command.
    }
  }

  Future<void> connect() => shortcuts.connect();
  Future<void> disconnect() => shortcuts.disconnect();
}

/// Called only by the headless entrypoint, after Flutter binding initialization.
Future<void> startSiriBackground(DeviceStore store) async {
  await store.reload();
  await SiriBackgroundSession(
    store: store,
    network: NetworkService(),
    agent: const AgentClient(),
  ).connect();
}

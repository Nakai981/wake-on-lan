import 'dart:convert';

import 'package:flutter/services.dart';

import 'agent_client.dart';
import 'models.dart';
import 'services.dart';

typedef SiriExecutor = Future<String> Function(
  String action,
  Pc pc,
  int delaySeconds,
);

/// Keeps device selection and credentials in Dart. Native Siri code receives
/// only a one-use ticket, the PC name and the delay shown in its confirmation.
class SiriShortcuts {
  static const channel = MethodChannel('wake_my_pc/siri');
  static const actions = {'wake', 'sleep', 'shutdown', 'cancel'};

  final DeviceStore store;
  final NetworkService network;
  final AgentClient agent;
  final List<Pc> Function() devices;
  final bool Function(Pc pc) isBusy;
  final SiriExecutor execute;
  final DateTime Function() now;
  final Future<void> Function()? refresh;
  _SiriTicket? _ticket;
  int _sequence = 0;
  bool _disposed = false;

  SiriShortcuts({
    required this.store,
    required this.network,
    required this.agent,
    required this.devices,
    required this.isBusy,
    required this.execute,
    this.refresh,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<void> connect() async {
    _disposed = false;
    channel.setMethodCallHandler(handle);
    await channel.invokeMethod<void>('ready');
  }

  Future<void> disconnect() async {
    _disposed = true;
    _ticket = null;
    channel.setMethodCallHandler(null);
    await channel.invokeMethod<void>('notReady');
  }

  Pc _defaultPc() {
    final selected = devices().where((pc) => pc.favorite).toList();
    if (selected.length != 1) {
      _fail(
        'no_default_pc',
        'Open Wake My PC and select one default PC in the device list.',
      );
    }
    return selected.single;
  }

  Never _fail(String code, String message) => throw _SiriFailure(code, message);

  Future<dynamic> handle(MethodCall call) async {
    try {
      if (_disposed) {
        _fail('not_ready', 'Open Wake My PC, then ask Siri again.');
      }
      final args = call.arguments;
      if (args is! Map) _fail('invalid_request', 'Invalid Siri request.');
      if (call.method == 'prepare' || call.method == 'execute') {
        await refresh?.call();
        if (_disposed) {
          _fail('not_ready', 'Open Wake My PC, then ask Siri again.');
        }
      }
      if (call.method == 'discard') {
        if (_ticket?.id == args['ticket']) _ticket = null;
        return null;
      }
      if (call.method == 'prepare') {
        _ticket = null;
        final action = args['action'];
        if (action is! String || !actions.contains(action)) {
          _fail('invalid_action', 'This Siri action is not supported.');
        }
        final pc = _defaultPc();
        if (action != 'cancel' && isBusy(pc)) {
          _fail('busy', 'A command for this PC is already in progress.');
        }
        if (action != 'wake' &&
            (!pc.agentPaired || await agent.keyFor(pc.id) == null)) {
          _fail(
            'not_paired',
            'Open Wake My PC and pair this PC with Windows Agent first.',
          );
        }
        await _checkNetwork(pc, action);
        final ticket = _SiriTicket(
          id: '${++_sequence}',
          action: action,
          pc: pc,
          delay: store.powerDelaySeconds,
          expires: now().add(const Duration(minutes: 2)),
        );
        _ticket = ticket;
        return {'ticket': ticket.id, 'name': pc.name, 'delay': ticket.delay};
      }
      if (call.method == 'execute') {
        final ticket = _ticket;
        // Consume before any await: the same confirmation can never send twice.
        _ticket = null;
        if (ticket == null ||
            ticket.id != args['ticket'] ||
            !now().isBefore(ticket.expires)) {
          _fail(
            'expired',
            'This Siri request has expired. Please ask Siri again.',
          );
        }
        final pc = _defaultPc();
        if (jsonEncode(pc.toJson()) != jsonEncode(ticket.pc.toJson()) ||
            store.powerDelaySeconds != ticket.delay) {
          _fail(
            'settings_changed',
            'Your PC settings changed. Please ask Siri again.',
          );
        }
        await _checkNetwork(pc, ticket.action);
        await refresh?.call();
        // Network permission/read can yield while the user edits or closes Home.
        if (_disposed) {
          _fail('not_ready', 'Open Wake My PC, then ask Siri again.');
        }
        if (jsonEncode(_defaultPc().toJson()) !=
                jsonEncode(ticket.pc.toJson()) ||
            store.powerDelaySeconds != ticket.delay) {
          _fail(
            'settings_changed',
            'Your PC settings changed. Please ask Siri again.',
          );
        }
        if (ticket.action != 'cancel' && isBusy(pc)) {
          _fail('busy', 'A command for this PC is already in progress.');
        }
        return await execute(ticket.action, pc, ticket.delay);
      }
      throw MissingPluginException('Unknown Siri method: ${call.method}');
    } on _SiriFailure {
      rethrow;
    } on MissingPluginException {
      rethrow;
    } catch (_) {
      // Do not pass Vietnamese transport errors or stored data to Siri.
      _fail(
        'request_failed',
        'The request could not be completed. Open Wake My PC to check your settings and connection.',
      );
    }
  }

  Future<void> _checkNetwork(Pc pc, String action) async {
    final lan = await network.network();
    if (lan == null) {
      _fail(
        'no_wifi',
        'Connect your iPhone to the same Wi-Fi network as your PC and allow Local Network access.',
      );
    }
    if (pc.network.isNotEmpty && pc.network != lan.key) {
      _fail(
        'network_changed',
        'The network has changed. Open Wake My PC and update this PC first.',
      );
    }
    if (action == 'wake') {
      if (pc.broadcast.isNotEmpty && !lan.contains(pc.broadcast)) {
        _fail(
          'invalid_broadcast',
          'Open Wake My PC and update this PC\'s broadcast address.',
        );
      }
    } else if (pc.ip.isEmpty || !lan.contains(pc.ip)) {
      _fail(
        'invalid_ip',
        'Open Wake My PC and set a PC address on your current network.',
      );
    }
  }
}

class _SiriFailure extends PlatformException {
  _SiriFailure(String code, String message)
    : super(code: code, message: message);
}

class _SiriTicket {
  final String id, action;
  final Pc pc;
  final int delay;
  final DateTime expires;
  const _SiriTicket({
    required this.id,
    required this.action,
    required this.pc,
    required this.delay,
    required this.expires,
  });
}

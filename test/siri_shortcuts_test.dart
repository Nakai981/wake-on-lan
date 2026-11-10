import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/siri_shortcuts.dart';

class SiriNetwork extends NetworkService {
  Lan? lan = Lan('192.168.1.20', '255.255.255.0');
  Future<Lan?> Function()? readNetwork;
  @override
  Future<Lan?> network() async => readNetwork == null ? lan : readNetwork!();
}

class SiriAgent extends AgentClient {
  String? key = '0123456789abcdef0123456789abcdef';
  @override
  Future<String?> keyFor(String id) async => key;
}

const defaultPc = Pc(
  id: 'studio',
  name: 'Studio PC',
  mac: 'A4:BB:6D:12:34:56',
  ip: '192.168.1.10',
  network: '192.168.1.0/255.255.255.0',
  favorite: true,
  agentPaired: true,
);

Matcher failsWith(String code) =>
    throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceStore store;
  late SiriNetwork net;
  late SiriAgent agent;
  late List<Pc> devices;
  late List<String> sent;
  late SiriShortcuts siri;
  late DateTime clock;
  var busy = false;

  Future<Map<dynamic, dynamic>> prepare(String action) async =>
      await siri.handle(MethodCall('prepare', {'action': action})) as Map;
  Future<dynamic> run(Map<dynamic, dynamic> ticket) =>
      siri.handle(MethodCall('execute', {'ticket': ticket['ticket']}));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = DeviceStore(await SharedPreferences.getInstance());
    net = SiriNetwork();
    agent = SiriAgent();
    devices = [defaultPc];
    sent = [];
    busy = false;
    clock = DateTime(2026, 11, 10);
    siri = SiriShortcuts(
      store: store,
      network: net,
      agent: agent,
      devices: () => devices,
      isBusy: (_) => busy,
      now: () => clock,
      execute: (action, pc, delay) async {
        sent.add('$action:${pc.id}:$delay');
        return 'Command received.';
      },
    );
  });

  test(
    'preparation sends nothing and never exposes the pairing secret',
    () async {
      final ticket = await prepare('shutdown');
      expect(ticket.keys, unorderedEquals(['ticket', 'name', 'delay']));
      expect(ticket['name'], 'Studio PC');
      expect(ticket.toString(), isNot(contains(agent.key!)));
      expect(sent, isEmpty);
      await siri.handle(MethodCall('discard', {'ticket': ticket['ticket']}));
      await expectLater(run(ticket), failsWith('expired'));
      expect(sent, isEmpty);
    },
  );

  for (final action in SiriShortcuts.actions) {
    test('$action uses the selected PC and saved delay exactly once', () async {
      await store.savePowerDelay(30);
      final ticket = await prepare(action);
      expect(ticket['delay'], 30);
      expect(await run(ticket), 'Command received.');
      expect(sent, ['$action:studio:30']);
      await expectLater(run(ticket), failsWith('expired'));
      expect(sent.length, 1);
    });
  }

  test('wake works without Agent pairing or a saved IP', () async {
    devices = [
      const Pc(
        id: 'wake-only',
        name: 'PC',
        mac: 'A4:BB:6D:12:34:56',
        favorite: true,
      ),
    ];
    agent.key = null;
    await run(await prepare('wake'));
    expect(sent.single, 'wake:wake-only:10');
  });

  test('does not silently choose the first PC without one default', () async {
    devices = [defaultPc.copy(favorite: false)];
    await expectLater(prepare('wake'), failsWith('no_default_pc'));
    devices = [defaultPc, defaultPc.copy()];
    await expectLater(prepare('wake'), failsWith('no_default_pc'));
    expect(sent, isEmpty);
  });

  test('rejects unknown actions and execution without preparation', () async {
    await expectLater(prepare('reboot'), failsWith('invalid_action'));
    await expectLater(
      siri.handle(const MethodCall('execute', {'ticket': '1'})),
      failsWith('expired'),
    );
    expect(sent, isEmpty);
  });

  test(
    'power actions require both paired flag and secure storage key',
    () async {
      devices = [defaultPc.copy(agentPaired: false)];
      await expectLater(prepare('sleep'), failsWith('not_paired'));
      devices = [defaultPc];
      agent.key = null;
      await expectLater(prepare('shutdown'), failsWith('not_paired'));
      await expectLater(prepare('cancel'), failsWith('not_paired'));
      expect(sent, isEmpty);
    },
  );

  test(
    'blocks offline, changed subnet, invalid IP and stale broadcast',
    () async {
      net.lan = null;
      await expectLater(prepare('wake'), failsWith('no_wifi'));
      net.lan = Lan('192.168.2.20', '255.255.255.0');
      await expectLater(prepare('wake'), failsWith('network_changed'));
      net.lan = Lan('192.168.1.20', '255.255.255.0');
      devices = [defaultPc.copy(ip: '192.168.2.10')];
      await expectLater(prepare('shutdown'), failsWith('invalid_ip'));
      devices = [
        const Pc(
          id: 'pc',
          name: 'PC',
          mac: 'A4:BB:6D:12:34:56',
          favorite: true,
          broadcast: '192.168.2.255',
        ),
      ];
      await expectLater(prepare('wake'), failsWith('invalid_broadcast'));
      expect(sent, isEmpty);
    },
  );

  test('expired and superseded confirmations cannot send', () async {
    final old = await prepare('shutdown');
    final current = await prepare('sleep');
    // An invalid ticket fails closed and consumes the current preparation too.
    await expectLater(run(old), failsWith('expired'));
    await expectLater(run(current), failsWith('expired'));
    final expired = await prepare('shutdown');
    clock = clock.add(const Duration(minutes: 2));
    await expectLater(run(expired), failsWith('expired'));
    expect(sent, isEmpty);
  });

  test(
    'PC edits, deselection, deletion and delay changes invalidate confirmation',
    () async {
      var ticket = await prepare('shutdown');
      devices = [defaultPc.copy(ip: '192.168.1.11')];
      await expectLater(run(ticket), failsWith('settings_changed'));
      devices = [defaultPc];
      ticket = await prepare('shutdown');
      devices = [defaultPc.copy(favorite: false)];
      await expectLater(run(ticket), failsWith('no_default_pc'));
      devices = [defaultPc];
      ticket = await prepare('shutdown');
      devices = [];
      await expectLater(run(ticket), failsWith('no_default_pc'));
      devices = [defaultPc];
      ticket = await prepare('shutdown');
      await store.savePowerDelay(60);
      await expectLater(run(ticket), failsWith('settings_changed'));
      expect(sent, isEmpty);
    },
  );

  test(
    'rechecks network after confirmation and never retries failure',
    () async {
      final ticket = await prepare('shutdown');
      net.lan = null;
      await expectLater(run(ticket), failsWith('no_wifi'));
      net.lan = Lan('192.168.1.20', '255.255.255.0');
      await expectLater(run(ticket), failsWith('expired'));
      expect(sent, isEmpty);
    },
  );

  test('rechecks selection after an asynchronous network read', () async {
    final ticket = await prepare('shutdown');
    final pending = Completer<Lan?>();
    net.readNetwork = () => pending.future;
    final execution = run(ticket);
    devices = [defaultPc.copy(ip: '192.168.1.11')];
    pending.complete(net.lan);
    await expectLater(execution, failsWith('settings_changed'));
    expect(sent, isEmpty);
  });

  test(
    'busy commands are blocked but pending power can still be cancelled',
    () async {
      var ticket = await prepare('shutdown');
      busy = true;
      await expectLater(run(ticket), failsWith('busy'));
      await expectLater(prepare('wake'), failsWith('busy'));
      ticket = await prepare('cancel');
      await run(ticket);
      expect(sent, ['cancel:studio:10']);
    },
  );

  test(
    'transport errors are returned to Siri in English without raw details',
    () async {
      for (final error in [
        const SocketException('Lỗi bí mật'),
        PlatformException(code: 'native_error', message: 'Lỗi bí mật'),
      ]) {
        net.readNetwork = () => throw error;
        await expectLater(
          prepare('wake'),
          throwsA(
            isA<PlatformException>()
                .having((e) => e.code, 'code', 'request_failed')
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('Lỗi bí mật')),
                ),
          ),
        );
      }
      expect(sent, isEmpty);
    },
  );

  test(
    'channel readiness handshake and disconnect invalidate in-flight work',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SiriShortcuts.channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SiriShortcuts.channel, null),
      );
      await siri.connect();
      final ticket = await prepare('shutdown');
      final pending = Completer<Lan?>();
      net.readNetwork = () => pending.future;
      final execution = run(ticket);
      await siri.disconnect();
      pending.complete(net.lan);
      await expectLater(execution, failsWith('not_ready'));
      expect(calls, ['ready', 'notReady']);
      expect(sent, isEmpty);
    },
  );
}

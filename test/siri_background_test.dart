import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/siri_background.dart';
import 'package:wake_my_pc/siri_shortcuts.dart';

class BackgroundNetwork extends NetworkService {
  int sends = 0;
  Lan? lan = Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<Lan?> network() async => lan;
  @override
  Future<void> wake(Pc pc, Lan lan) async {
    sends++;
  }
}

class BackgroundAgent extends AgentClient {
  final commands = <String>[];
  String result = 'accepted';
  bool fail = false;
  @override
  Future<String?> keyFor(String id) async => '0123456789abcdef0123456789abcdef';
  @override
  Future<String> command(Pc pc, String command) async {
    commands.add(command);
    if (fail) throw const SocketException('Connection lost');
    return command == 'cancel' ? 'cancelled' : result;
  }
}

class LoopbackBackgroundNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => Lan('127.0.0.1', '255.0.0.0');
}

class FailingHistoryStore extends DeviceStore {
  FailingHistoryStore(super.prefs);
  @override
  Future<void> log(String text) async =>
      throw const FileSystemException('Full');
}

const pc = Pc(
  id: 'studio',
  name: 'Studio PC',
  mac: 'A4:BB:6D:12:34:56',
  ip: '192.168.1.10',
  favorite: true,
  agentPaired: true,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceStore store;
  late BackgroundNetwork network;
  late BackgroundAgent agent;
  late SiriBackgroundSession session;

  Future<Map> prepare(String action) async =>
      await session.shortcuts.handle(MethodCall('prepare', {'action': action}))
          as Map;
  Future<dynamic> execute(Map ticket) => session.shortcuts.handle(
    MethodCall('execute', {'ticket': ticket['ticket']}),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = DeviceStore(await SharedPreferences.getInstance());
    await store.save([pc]);
    await store.savePowerDelay(30);
    network = BackgroundNetwork();
    agent = BackgroundAgent();
    session = SiriBackgroundSession(
      store: store,
      network: network,
      agent: agent,
    );
  });

  test('iOS entrypoint handshakes without mounting the app', () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SiriShortcuts.channel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(() {
      SiriShortcuts.channel.setMethodCallHandler(null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SiriShortcuts.channel,
        null,
      );
    });
    await siriBackgroundMain();
    expect(calls, ['ready']);
    expect(binding.rootElement, isNull);
  });

  for (final action in ['wake', 'sleep', 'shutdown', 'cancel']) {
    test(
      'background $action runs without mounting Home and records accepted work',
      () async {
        expect(binding.rootElement, isNull);
        final ticket = await prepare(action);
        expect(network.sends, 0);
        expect(agent.commands, isEmpty);
        final result = await execute(ticket) as String;
        if (action == 'wake') {
          expect(network.sends, 1);
          expect(result, contains('does not confirm'));
          expect(store.read().single.lastWake, isNotNull);
        } else {
          expect(
            agent.commands.single,
            action == 'cancel' ? 'cancel' : 'power:$action:30',
          );
          expect(
            result,
            contains(
              action == 'cancel' ? 'cancelled' : 'scheduled in 30 seconds',
            ),
          );
        }
        expect(store.history().single, contains('Siri'));
        expect(store.siriActivityVersion, 1);
        expect(store.siriActivityPcId, pc.id);
        expect(binding.rootElement, isNull);
        await expectLater(execute(ticket), throwsA(isA<PlatformException>()));
        expect(network.sends + agent.commands.length, 1);
      },
    );
  }

  test(
    'cancelling native confirmation never sends a background command',
    () async {
      final ticket = await prepare('shutdown');
      await session.shortcuts.handle(
        MethodCall('discard', {'ticket': ticket['ticket']}),
      );
      await expectLater(execute(ticket), throwsA(isA<PlatformException>()));
      expect(agent.commands, isEmpty);
      expect(store.history(), isEmpty);
    },
  );

  for (final response in ['busy', 'simulated', 'unsupported']) {
    test(
      'background $response is not recorded as an accepted power action',
      () async {
        agent.result = response;
        final result = await execute(await prepare('shutdown')) as String;
        expect(result, isNot(contains('It is scheduled in')));
        expect(agent.commands.length, 1);
        expect(store.history(), isEmpty);
        expect(store.siriActivityVersion, 0);
      },
    );
  }

  test('connection loss is ambiguous and is never retried', () async {
    agent.fail = true;
    final ticket = await prepare('shutdown');
    expect(await execute(ticket), contains('may have reached your PC'));
    await expectLater(execute(ticket), throwsA(isA<PlatformException>()));
    expect(agent.commands.length, 1);
    expect(store.history(), isEmpty);
  });

  test(
    'a second engine sees native preference changes during confirmation',
    () async {
      final ticket = await prepare('shutdown');
      // Replace the native backing store without updating this isolate's cache.
      SharedPreferences.setMockInitialValues({
        'devices': jsonEncode([pc.copy(ip: '192.168.1.11').toJson()]),
        'powerDelaySeconds': 60,
      });
      await expectLater(
        execute(ticket),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'settings_changed',
          ),
        ),
      );
      expect(agent.commands, isEmpty);
    },
  );

  test('headless channel answers native calls without a widget tree', () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SiriShortcuts.channel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SiriShortcuts.channel,
        null,
      ),
    );
    await session.connect();
    const codec = StandardMethodCodec();
    Future<dynamic> nativeCall(String method, Map args) async {
      final response = Completer<dynamic>();
      binding.channelBuffers.push(
        SiriShortcuts.channel.name,
        codec.encodeMethodCall(MethodCall(method, args)),
        (reply) {
          try {
            response.complete(codec.decodeEnvelope(reply!));
          } catch (e, stack) {
            response.completeError(e, stack);
          }
        },
      );
      return response.future;
    }

    final ticket = await nativeCall('prepare', {'action': 'wake'}) as Map;
    expect(
      await nativeCall('execute', {'ticket': ticket['ticket']}),
      contains('wake signal was sent'),
    );
    await session.disconnect();
    expect(calls, ['ready', 'notReady']);
    expect(network.sends, 1);
    expect(binding.rootElement, isNull);
  });

  test('history failure after sending never resends the wake packet', () async {
    session = SiriBackgroundSession(
      store: FailingHistoryStore(store.prefs),
      network: network,
      agent: agent,
    );
    expect(
      await execute(await prepare('wake')),
      contains('wake signal was sent'),
    );
    expect(network.sends, 1);
  });

  test(
    'background session sends real Magic Packets only to UDP loopback',
    () async {
      final receiver = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final packets = <List<int>>[];
      final delivered = Completer<void>();
      final subscription = receiver.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = receiver.receive()) != null) {
          packets.add(datagram!.data);
          if (packets.length == 2 && !delivered.isCompleted) {
            delivered.complete();
          }
        }
      });
      try {
        await store.save([
          Pc(
            id: 'loopback',
            name: 'Loopback PC',
            mac: pc.mac,
            ip: '127.0.0.1',
            broadcast: '127.0.0.1',
            port: receiver.port,
            retries: 2,
            favorite: true,
          ),
        ]);
        session = SiriBackgroundSession(
          store: store,
          network: LoopbackBackgroundNetwork(),
          agent: agent,
        );
        expect(
          await execute(await prepare('wake')),
          contains('wake signal was sent'),
        );
        await delivered.future.timeout(const Duration(seconds: 3));
        expect(packets, [magicPacket(pc.mac), magicPacket(pc.mac)]);
        expect(agent.commands, isEmpty);
        expect(binding.rootElement, isNull);
      } finally {
        await subscription.cancel();
        receiver.close();
      }
    },
  );
}

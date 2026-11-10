import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/siri_shortcuts.dart';

class HomeSiriNetwork extends NetworkService {
  int wakes = 0;
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<bool> reachable(String ip) async => false;
  @override
  Future<void> wake(Pc pc, Lan lan) async {
    wakes++;
  }
}

class HomeSiriAgent extends AgentClient {
  final commands = <String>[];
  String response = 'accepted';
  @override
  Future<String?> keyFor(String id) async => '0123456789abcdef0123456789abcdef';
  @override
  Future<String> command(Pc pc, String command) async {
    commands.add(command);
    if (command == 'status') return 'online';
    return command == 'cancel' ? 'cancelled' : response;
  }
}

Future<dynamic> nativeCall(WidgetTester tester, String method, Map args) async {
  const codec = StandardMethodCodec();
  final reply = Completer<ByteData?>();
  tester.binding.channelBuffers.push(
    SiriShortcuts.channel.name,
    codec.encodeMethodCall(MethodCall(method, args)),
    reply.complete,
  );
  // Advance callbacks without waiting for ongoing wake/status animations.
  for (var i = 0; i < 30 && !reply.isCompleted; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    reply.isCompleted,
    isTrue,
    reason: 'Flutter must answer the native Siri call',
  );
  return codec.decodeEnvelope((await reply.future)!);
}

void main() {
  for (final action in ['wake', 'sleep', 'shutdown']) {
    testWidgets('native $action uses Home transport, history and power delay', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nativeCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SiriShortcuts.channel,
        (call) async {
          nativeCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SiriShortcuts.channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.savePowerDelay(30);
      await store.save([
        const Pc(
          id: 'studio',
          name: 'Studio PC',
          mac: 'A4:BB:6D:12:34:56',
          ip: '192.168.1.10',
          favorite: true,
          agentPaired: true,
        ),
      ]);
      final network = HomeSiriNetwork();
      final agent = HomeSiriAgent();
      await tester.pumpWidget(
        WakeApp(store: store, network: network, agentClient: agent),
      );
      await tester.pumpAndSettle();
      expect(nativeCalls, ['ready']);

      var ticket =
          await nativeCall(tester, 'prepare', {'action': action}) as Map;
      expect(network.wakes, 0);
      expect(agent.commands.where((command) => command != 'status'), isEmpty);
      // This simulates declining Siri's confirmation before native execute.
      await nativeCall(tester, 'discard', {'ticket': ticket['ticket']});
      expect(store.history(), isEmpty);
      ticket = await nativeCall(tester, 'prepare', {'action': action}) as Map;
      final result = await nativeCall(tester, 'execute', {
        'ticket': ticket['ticket'],
      }) as String;
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Power confirmation has already been collected by native Siri',
      );
      if (action == 'wake') {
        expect(network.wakes, 1);
        expect(result, contains('wake signal was sent'));
        expect(result, contains('does not confirm'));
        expect(store.read().single.lastWake, isNotNull);
        expect(store.history().single, contains('Đã gửi Wake'));
      } else {
        expect(
          agent.commands.where((command) => command != 'status').single,
          'power:$action:30',
        );
        expect(result, contains('scheduled in 30 seconds'));
        expect(store.history().single, contains('chờ 30 giây'));
        final cancel =
            await nativeCall(tester, 'prepare', {'action': 'cancel'}) as Map;
        expect(
          await nativeCall(tester, 'execute', {'ticket': cancel['ticket']}),
          'The pending power command was cancelled.',
        );
        expect(agent.commands, contains('cancel'));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(nativeCalls.last, 'notReady');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  for (final response in ['busy', 'simulated', 'unsupported']) {
    testWidgets('Siri does not report success when Agent responds $response', (
      tester,
    ) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SiriShortcuts.channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SiriShortcuts.channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.save([
        const Pc(
          id: 'studio',
          name: 'Studio PC',
          mac: 'A4:BB:6D:12:34:56',
          ip: '192.168.1.10',
          favorite: true,
          agentPaired: true,
        ),
      ]);
      final agent = HomeSiriAgent()..response = response;
      await tester.pumpWidget(
        WakeApp(store: store, network: HomeSiriNetwork(), agentClient: agent),
      );
      await tester.pumpAndSettle();
      final ticket =
          await nativeCall(tester, 'prepare', {'action': 'shutdown'}) as Map;
      final result = await nativeCall(tester, 'execute', {
        'ticket': ticket['ticket'],
      }) as String;
      expect(result, isNot(contains('It is scheduled in')));
      expect(store.history(), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

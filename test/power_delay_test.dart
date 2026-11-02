import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/power_delay.dart';
import 'package:wake_my_pc/services.dart';

class DelayNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
}

class DelayAgent extends AgentClient {
  final commands = <String>[];
  @override
  Future<String> command(Pc pc, String command) async {
    commands.add(command);
    return command == 'status' ? 'online' : 'accepted';
  }
}

void main() {
  test(
    'delay defaults, bounds and persistence across store instances',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = DeviceStore(prefs);
      expect(store.powerDelaySeconds, 10);
      await store.savePowerDelay(300);
      expect(DeviceStore(prefs).powerDelaySeconds, 300);
      for (final invalid in [0, -1, 86401]) {
        await expectLater(store.savePowerDelay(invalid), throwsFormatException);
      }
      expect(store.powerDelaySeconds, 300);
      await prefs.setInt('powerDelaySeconds', 0);
      expect(DeviceStore(prefs).powerDelaySeconds, 10);
    },
  );

  test('power protocol bounds and backwards compatible default', () {
    for (final action in ['sleep', 'shutdown']) {
      expect(powerDelayCommand(action, 10), action);
      expect(powerDelayCommand(action, 30), 'power:$action:30');
      expect(validPowerDelayCommand('power:$action:1'), isTrue);
      expect(validPowerDelayCommand('power:$action:86400'), isTrue);
    }
    for (final bad in [
      'power:sleep:0',
      'power:sleep:-1',
      'power:sleep:86401',
      'power:sleep:01',
      'power:reboot:30',
      'power:shutdown:30:extra',
    ]) {
      expect(validPowerDelayCommand(bad), isFalse);
    }
    expect(() => powerDelayCommand('reboot', 30), throwsArgumentError);
  });

  for (final action in ['sleep', 'shutdown']) {
    testWidgets('menu saves shared delay, reused after restart for $action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = DeviceStore(prefs);
      await store.save([
        const Pc(
          id: 'pc',
          name: 'Studio',
          mac: 'A4:BB:6D:12:34:56',
          ip: '192.168.1.10',
          agentPaired: true,
          favorite: true,
        ),
      ]);
      final agent = DelayAgent();
      await tester.pumpWidget(
        WakeApp(store: store, network: DelayNetwork(), agentClient: agent),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mở menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thời gian chờ tắt / Sleep'));
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField);
      await tester.enterText(field, '0');
      await tester.tap(find.text('Lưu thời gian chờ'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập số từ 1 đến 86400.'), findsOneWidget);
      expect(store.powerDelaySeconds, 10);
      await tester.enterText(field, '30');
      await tester.tap(find.text('Lưu thời gian chờ'));
      await tester.pumpAndSettle();
      expect(store.powerDelaySeconds, 30);
      expect(agent.commands.where((c) => c != 'status'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        WakeApp(
          store: DeviceStore(prefs),
          network: DelayNetwork(),
          agentClient: agent,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(action == 'sleep' ? 'Sleep' : 'Shutdown'));
      await tester.pumpAndSettle();
      expect(find.textContaining('30 giây'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        agent.commands.where((c) => c != 'status').single,
        'power:$action:30',
      );
      // The old 20-second status check must not run before the 30-second delay.
      final checks = agent.commands.where((c) => c == 'status').length;
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(agent.commands.where((c) => c == 'status').length, checks);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(
        agent.commands.where((c) => c == 'status').length,
        greaterThan(checks),
      );
    });
  }
}

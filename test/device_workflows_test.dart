import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/agent_pair.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/setup.dart';
import 'package:wake_my_pc/wake_console.dart';

const pc = Pc(
  id: 'saved',
  name: 'Studio',
  mac: 'A4:BB:6D:12:34:56',
  ip: '192.168.1.10',
  favorite: true,
);

class TestNetwork extends NetworkService {
  bool online = false;
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<bool> reachable(String ip) async => online;
  @override
  Future<void> wake(Pc pc, Lan lan) async {}
  @override
  Future<String?> macFor(String ip) async => null;
  @override
  Future<String?> nameFor(String ip) =>
      throw StateError('Name must be entered by user');
  @override
  Future<void> scan(
    Lan lan, {
    required bool Function() cancelled,
    required void Function(int, int, String?) progress,
  }) async => progress(1, 1, pc.ip);
}

class SavedAgent extends AgentClient {
  final commands = <String>[];
  @override
  Future<String> command(Pc pc, String command) async {
    commands.add(command);
    return command == 'status' ? 'online' : 'accepted';
  }

  @override
  Future<String> request(
    String ip,
    String code,
    String command, {
    int port = agentPort,
  }) async => 'online';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<DeviceStore> store(Pc device) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await DeviceStore(prefs).save([device]);
    return DeviceStore(prefs);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
  }

  test(
    'pairing key and paired flag survive new clients and store instances',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      await SavedAgent().pair(pc, '0123456789abcdef0123456789abcdef');
      final saved = await store(pc.copy(agentPaired: true));
      expect(saved.read().single.agentPaired, isTrue);
      expect(
        await const AgentClient().keyFor(saved.read().single.id),
        '0123456789abcdef0123456789abcdef',
      );
    },
  );

  for (final command in ['sleep', 'shutdown']) {
    testWidgets('saved pairing opens $command confirmation after app restart', (
      tester,
    ) async {
      phone(tester);
      final saved = await store(pc.copy(agentPaired: true));
      final agent = SavedAgent();
      await tester.pumpWidget(
        WakeApp(store: saved, network: TestNetwork(), agentClient: agent),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đang hoạt động'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        WakeApp(store: saved, network: TestNetwork(), agentClient: agent),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(command == 'sleep' ? 'Sleep' : 'Shutdown'));
      await tester.pumpAndSettle();
      expect(find.byType(AgentPairPage), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(agent.commands.where((value) => value == command), hasLength(1));
      expect(saved.read().single.agentPaired, isTrue);
    });
  }

  for (final closeEarly in [false, true]) {
    testWidgets(
      'wake updates Home and closes only its console (closed early: $closeEarly)',
      (tester) async {
        phone(tester);
        final net = TestNetwork();
        await tester.pumpWidget(WakeApp(store: await store(pc), network: net));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(WakeConsolePage), findsOneWidget);
        if (closeEarly) {
          await tester.tap(find.text('Đóng console'));
          await tester.pumpAndSettle();
        }
        net.online = true;
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byType(WakeConsolePage), findsNothing);
        expect(find.text('Đang hoạt động'), findsOneWidget);
        expect(find.text('Shutdown'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'LAN and manual entry share form; missing MAC permits manual completion',
    (tester) async {
      phone(tester);
      Pc? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Pc>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SetupPage(net: TestNetwork()),
                    ),
                  );
                },
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LAN / Nhập tay'));
      await tester.pumpAndSettle();
      // Locate fields by their descendant InputDecorator to avoid relying on order.
      Finder input(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(input('Tên máy tính'), 'Máy làm việc');
      await tester.tap(find.text('Quét LAN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pc.ip));
      await tester.pumpAndSettle();
      expect(find.text('Máy làm việc'), findsOneWidget);
      expect(find.textContaining('Không đọc được MAC qua LAN'), findsOneWidget);
      await tester.ensureVisible(input('MAC Ethernet'));
      await tester.enterText(input('MAC Ethernet'), pc.mac);
      await tester.ensureVisible(find.text('Hoàn tất'));
      await tester.tap(find.text('Hoàn tất'));
      await tester.pumpAndSettle();
      expect(result?.name, 'Máy làm việc');
      expect(result?.ip, pc.ip);
      expect(result?.mac, pc.mac);
    },
  );
}

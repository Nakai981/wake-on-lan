import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class NoNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
}

class FakeAgent extends AgentClient {
  @override
  Future<String> command(Pc pc, String command) async => 'online';
}

void main() {
  testWidgets(
    'paired PC exposes power controls and shutdown requires confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.save([
        const Pc(
          id: 'test',
          name: 'Studio',
          mac: 'A4:BB:6D:12:34:56',
          agentPaired: true,
          favorite: true,
          ip: '192.168.1.10',
        ),
      ]);
      await tester.pumpWidget(
        WakeApp(store: store, network: NoNetwork(), agentClient: FakeAgent()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sleep'), findsOneWidget);
      await tester.tap(find.text('Shutdown'));
      await tester.pumpAndSettle();
      expect(find.text('Tắt máy Studio?'), findsOneWidget);
      expect(find.textContaining('Lưu công việc'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Tắt máy Studio?'), findsNothing);
      expect(store.history(), isEmpty);
    },
  );
  test(
    'existing device migration defaults unpaired; edits preserve pairing',
    () {
      final old = Pc.fromJson({
        'id': '1',
        'name': 'PC',
        'mac': 'A4:BB:6D:12:34:56',
      });
      expect(old.agentPaired, isFalse);
      final paired = old.copy(agentPaired: true).copy(favorite: true);
      expect(Pc.fromJson(paired.toJson()).agentPaired, isTrue);
      expect(paired.toJson().containsKey('secret'), isFalse);
    },
  );
}

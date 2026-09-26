import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class StateNetwork extends NetworkService {
  bool online = false;
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<bool> reachable(String ip) async => online;
}

void main() {
  testWidgets(
    'one star selects Home; real status switches black and light controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.save([
        const Pc(
          id: '1',
          name: 'Gaming PC',
          mac: 'A4:BB:6D:12:34:56',
          ip: '192.168.1.10',
          favorite: true,
        ),
        const Pc(
          id: '2',
          name: 'Office PC',
          mac: 'A4:BB:6D:12:34:58',
          ip: '192.168.1.11',
        ),
      ]);
      final net = StateNetwork();
      await tester.pumpWidget(WakeApp(store: store, network: net));
      await tester.pumpAndSettle();
      expect(find.text('Gaming PC'), findsOneWidget);
      expect(find.text('Office PC'), findsNothing);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.black,
      );
      expect(find.text('BẬT PC'), findsOneWidget);
      await tester.tap(find.text('Danh sách'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chọn Office PC cho Home'));
      await tester.pumpAndSettle();
      expect(store.read().where((p) => p.favorite).single.id, '2');
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Office PC'), findsOneWidget);
      expect(find.text('Gaming PC'), findsNothing);
      net.online = true;
      await tester.tap(find.byTooltip('Kiểm tra lại'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        paper,
      );
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Shutdown'), findsOneWidget);
      expect(find.text('BẬT PC'), findsNothing);
      net.online = false;
      await tester.tap(find.byTooltip('Kiểm tra lại'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.black,
      );
      expect(find.text('BẬT PC'), findsOneWidget);
    },
  );
}

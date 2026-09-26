import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class WakeNetwork extends NetworkService {
  bool responds = false;
  int sends = 0;
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<void> wake(Pc pc, Lan lan) async {
    sends++;
  }

  @override
  Future<bool> reachable(String ip) async => responds;
}

void main() {
  for (final online in [true, false]) {
    testWidgets('Home sends immediately then checks at 10s: online=$online', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
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
          id: '1',
          name: 'Studio PC',
          mac: 'A4:BB:6D:12:34:56',
          ip: '192.168.1.10',
          favorite: true,
        ),
      ]);
      final net = WakeNetwork();
      await tester.pumpWidget(WakeApp(store: store, network: net));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(net.sends, 1);
      expect(find.text('Studio PC'), findsOneWidget);
      expect(
        find.text('Đã gửi tín hiệu khởi động đến Studio PC.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(button.onPressed, isNull);
      net.responds = online;
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Luôn có lời giải'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      if (online) {
        expect(find.text('Đang hoạt động'), findsOneWidget);
        expect(find.textContaining('đã khởi động thành công'), findsOneWidget);
        expect(find.text('Studio PC'), findsOneWidget);
      } else {
        expect(find.text('Luôn có lời giải'), findsOneWidget);
        expect(
          find.textContaining(
            'chưa xác nhận được máy đã khởi động sau khoảng 10 giây',
          ),
          findsOneWidget,
        );
      }
    });
  }
}

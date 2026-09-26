import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class UiNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<bool> reachable(String ip) async => false;
}

void main() {
  testWidgets('menu routes to history and help on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      WakeApp(
        store: DeviceStore(await SharedPreferences.getInstance()),
        network: UiNetwork(),
      ),
    );
    await tester.pumpAndSettle();
    if (find.byTooltip('Mở menu').evaluate().isEmpty) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Mở menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lịch sử hoạt động'));
    await tester.pumpAndSettle();
    expect(find.text('Một khởi đầu mới'), findsOneWidget);
    if (find.byTooltip('Mở menu').evaluate().isEmpty) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Mở menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hướng dẫn & trợ giúp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hướng dẫn & trợ giúp'));
    await tester.pumpAndSettle();
    expect(find.text('Luôn có lời giải'), findsOneWidget);
    // Framework reports any layout errors at test completion.
  });
  testWidgets('favorites filter and device action sheet remain functional', (
    tester,
  ) async {
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
        id: '1',
        name: 'Studio PC',
        mac: 'A4:BB:6D:12:34:56',
        favorite: true,
      ),
      const Pc(id: '2', name: 'Work PC', mac: 'A4:BB:6D:12:34:58'),
    ]);
    await tester.pumpWidget(WakeApp(store: store, network: UiNetwork()));
    await tester.pumpAndSettle();
    expect(find.text('Work PC'), findsNothing);
    await tester.tap(find.text('Danh sách'));
    await tester.pumpAndSettle();
    expect(find.text('Studio PC'), findsOneWidget);
    expect(find.text('Work PC'), findsOneWidget);
    await tester.tap(find.byTooltip('Tùy chọn máy').first);
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra cấu hình'), findsOneWidget);
    await tester.tap(find.text('Xóa máy'));
    await tester.pumpAndSettle();
    expect(find.text('Xóa “Studio PC”?'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(store.read().length, 2);
    // Framework reports any layout errors at test completion.
  });
}

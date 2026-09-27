import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/app_theme.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/remote_control.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class ThemeNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => null;
}

void main() {
  testWidgets('appearance follows tabs and routes without changing PC status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore(await SharedPreferences.getInstance());
    await store.save([
      const Pc(id: '1', name: 'PC', mac: 'AA:BB:CC:DD:EE:FF', favorite: true),
    ]);
    appThemeMode.value = ThemeMode.light;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      appThemeMode.value = ThemeMode.light;
    });
    await tester.pumpWidget(WakeApp(store: store, network: ThemeNetwork()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chuyển giao diện tối'));
    await tester.pumpAndSettle();
    expect(find.text('BẬT PC'), findsOneWidget);
    expect(find.text('Điều khiển · Xem trước'), findsNothing);
    await tester.tap(find.text('Danh sách'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('Trợ giúp'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byTooltip('Mở menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Điều khiển'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(RemoteControlPage))).brightness,
      Brightness.dark,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chuyển giao diện sáng'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
  });
}

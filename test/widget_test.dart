import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';

class FakeNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<bool> reachable(String ip) async => false;
}

void main() {
  testWidgets('onboarding saves a real device and home retains it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(WakeApp(store: store, network: FakeNetwork()));
    await tester.pumpAndSettle();
    expect(find.text('PC của bạn, trong tầm tay'), findsOneWidget);
    await tester.ensureVisible(find.text('Bắt đầu thiết lập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu thiết lập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tôi đã chuẩn bị xong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập máy thủ công'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'PC Gaming');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'a4-bb-6d-12-34-56',
    );
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu máy tính'));
    await tester.pumpAndSettle();
    expect(find.text('PC Gaming'), findsOneWidget);
    expect(store.read().single.mac, 'A4:BB:6D:12:34:56');
    expect(find.text('BẬT PC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid MAC prevents moving to save step', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      WakeApp(
        store: DeviceStore(await SharedPreferences.getInstance()),
        network: FakeNetwork(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bắt đầu thiết lập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu thiết lập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tôi đã chuẩn bị xong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập máy thủ công'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'PC');
    await tester.enterText(find.byType(TextFormField).at(1), 'invalid');
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nhập đủ 6 cặp'), findsOneWidget);
    expect(find.text('Lưu máy tính'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/agent_help.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/setup.dart';

class HelpNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
}

void main() {
  testWidgets('download opens the official EXE link in an external browser', (
    tester,
  ) async {
    MethodCall? request;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      request = call;
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: AgentHelpPage()));
    await tester.tap(find.text('Tải Windows Agent (.exe)'));
    await tester.pumpAndSettle();
    expect(request?.method, 'launch');
    expect(request?.arguments['url'], agentDownloadUrl);
    expect(request?.arguments['useWebView'], false);
    expect(request?.arguments['useSafariVC'], false);
  });

  for (final width in [320.0, 430.0]) {
    testWidgets('QR help returns to the unsaved PC at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: SetupPage(net: HelpNetwork())));
      await tester.pumpAndSettle();
      expect(find.text('Thêm PC bằng QR Agent'), findsOneWidget);
      final buttons = ['QR Agent', 'Quét LAN', 'Nhập tay']
          .map(
            (label) =>
                tester.getRect(find.widgetWithText(OutlinedButton, label)),
          )
          .toList();
      expect(buttons[0].width, closeTo(buttons[1].width, 0.01));
      expect(buttons[1].width, closeTo(buttons[2].width, 0.01));
      expect(
        buttons[1].left - buttons[0].right,
        closeTo(buttons[2].left - buttons[1].right, 0.01),
      );
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(
        find.byType(TextFormField).first,
        'PC phòng làm việc',
      );
      await tester.ensureVisible(find.text('Chưa có Agent? Trợ giúp'));
      await tester.tap(find.text('Chưa có Agent? Trợ giúp'));
      await tester.pumpAndSettle();
      expect(find.text('Trợ giúp Windows Agent'), findsOneWidget);
      expect(find.text('Tải Windows Agent (.exe)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Bạn giữ quyền kiểm soát'),
        180,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).first);
      expect(find.text('PC phòng làm việc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('help supports large text without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const AgentHelpPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Xem mã nguồn trên GitHub'), 300);
    expect(tester.takeException(), isNull);
  });
}

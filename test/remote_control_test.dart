import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/remote_control.dart';

void main() {
  testWidgets('unified controls expand and preserve Vietnamese input', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RemoteControlPage(pcName: 'Studio PC')),
    );
    expect(find.text('F1'), findsNothing);
    final submit = find.byTooltip('Thử nhập');
    await tester.enterText(find.byType(TextField), 'Xin chào');
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('Đã thử nhập 8 ký tự · chưa gửi đến PC'), findsOneWidget);
    await tester.tap(find.byTooltip('Mở rộng công cụ'));
    await tester.pumpAndSettle();
    expect(find.text('F1'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('function-strip')),
      const Offset(-420, 0),
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('function-strip')),
    );
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Thu gọn công cụ'));
    await tester.pumpAndSettle();
    expect(find.text('F1'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Xin chào',
    );
    expect(tester.takeException(), isNull);
  });
}

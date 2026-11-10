import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/app_theme.dart';
import 'package:wake_my_pc/design.dart';
import 'package:wake_my_pc/help.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/siri_help.dart';
import 'package:wake_my_pc/workspace.dart';

class HelpLayoutNetwork extends NetworkService {
  @override
  Future<Lan?> network() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader(uiFont);
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'Help reads in ${dark ? "dark" : "light"} at text scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          appThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            appThemeMode.value = ThemeMode.light;
          });
          SharedPreferences.setMockInitialValues({});
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: WakeApp(
                store: DeviceStore(await SharedPreferences.getInstance()),
                network: HelpLayoutNetwork(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Trợ giúp'));
          await tester.pumpAndSettle();
          expect(find.text('Hướng dẫn sử dụng'), findsOneWidget);
          await tester.tap(find.text('Siri trên iPhone'));
          await tester.pumpAndSettle();
          expect(find.byType(SiriHelpContent), findsOneWidget);
          final command = tester.widget<SelectableText>(
            find.byType(SelectableText).first,
          );
          expect(command.style?.fontFamily, uiFont);
          expect(command.style?.height, greaterThanOrEqualTo(1.5));
          final context = tester.element(find.byType(SiriHelpContent));
          final bg = Theme.of(context).colorScheme.primaryContainer
              .computeLuminance();
          final fg = command.style!.color!.computeLuminance();
          final contrast = fg > bg
              ? (fg + .05) / (bg + .05)
              : (bg + .05) / (fg + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));

          if (const bool.fromEnvironment('UPDATE_UI_PREVIEWS') && scale == 1) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('docs/help-${dark ? "dark" : "light"}.png')
                  .writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
          }

          final scrollable = find
              .descendant(
                of: find.byType(HelpContent),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.text('Shortcuts hỏi “Allow”?'),
            240,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Mở menu'));
          await tester.pumpAndSettle();
          final headerPosition = tester.getTopLeft(
            find.text('Không gian của bạn'),
          );
          await tester.scrollUntilVisible(
            find.text('Hướng dẫn & trợ giúp'),
            160,
            scrollable: find.descendant(
              of: find.byKey(WorkspaceSheet.scrollKey),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.text('Không gian của bạn')),
            headerPosition,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Đóng menu'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Windows Agent'),
            240,
            scrollable: scrollable,
          );
          await tester.tap(find.text('Windows Agent'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Xem mã nguồn trên GitHub'),
            240,
            scrollable: scrollable,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

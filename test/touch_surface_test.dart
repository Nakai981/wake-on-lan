import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/touch_surface.dart';

void main() {
  testWidgets(
    'bottom zones click and scroll activates after holding two seconds',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchSurface(
              height: 300,
              sensitivity: 1,
              dragging: false,
              onAction: actions.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mouse-left')));
      await tester.tap(find.byKey(const ValueKey('mouse-right')));
      expect(actions, ['Nhấp trái', 'Nhấp phải']);
      final strip = find.byKey(const ValueKey('scroll-strip'));
      final gesture = await tester.startGesture(tester.getCenter(strip));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        .08,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveBy(const Offset(0, 20));
      expect(actions.last, 'Cuộn xuống');
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        .08,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

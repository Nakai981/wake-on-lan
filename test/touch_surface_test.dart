import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/touch_surface.dart';

void main() {
  testWidgets(
    'bottom zones click and both swipe directions reveal scroll immediately',
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
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        .08,
      );
      await gesture.moveBy(const Offset(0, 25));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      expect(actions.last, 'Cuộn xuống');
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        .08,
      );
      final upward = await tester.startGesture(tester.getCenter(strip));
      await upward.moveBy(const Offset(0, -25));
      await upward.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(actions.last, 'Cuộn lên');
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      await upward.up();
      await tester.pumpWidget(const SizedBox());
    },
  );
}

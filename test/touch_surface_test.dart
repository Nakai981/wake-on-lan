import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/touch_surface.dart';

void main() {
  testWidgets('touchpad captures first movement without scrolling parent', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              TouchSurface(
                height: 300,
                sensitivity: 1,
                dragging: false,
                onAction: (_) {},
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );
    final dot = find.byKey(const ValueKey('touch-cursor'));
    final start = tester.getCenter(dot);
    final gesture = await tester.startGesture(const Offset(150, 120));
    await gesture.moveBy(const Offset(0, -3));
    await tester.pump();
    expect(tester.getCenter(dot).dy, lessThan(start.dy));
    await gesture.moveBy(const Offset(0, -60));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    await tester.dragFrom(const Offset(150, 430), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
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

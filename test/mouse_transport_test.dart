import 'package:flutter_test/flutter_test.dart';
import 'package:wake_my_pc/mouse_transport.dart';

void main() {
  testWidgets('motion coalesces, clicks keep order, dragging is released', (tester) async {
    final commands = <String>[];
    final mouse = MouseTransport(send: (cmd) async { commands.add(cmd); return 'input_ok'; }, onError: () => fail('Unexpected error'));
    mouse.move(4, 6); mouse.move(7, -2); mouse.click(false); mouse.wheel(20);
    await tester.pump(const Duration(milliseconds: 30));
    expect(commands.map((s) => s.split(':').skip(2).join(':')).toList(), ['move:11:4', 'left', 'wheel:-120']);
    final down = mouse.drag(true);
    await tester.pump(const Duration(milliseconds: 30));
    expect(await down, isTrue);
    await tester.pump(const Duration(milliseconds: 520));
    await tester.pump(const Duration(milliseconds: 30));
    expect(commands.last.endsWith(':hold'), isTrue);
    mouse.dispose();
    await tester.pump(const Duration(milliseconds: 30));
    expect(commands.last.endsWith(':up'), isTrue);
  });
  testWidgets('failed mouse acknowledgement clears queued clicks and releases', (tester) async {
    final commands = <String>[];
    var errors = 0;
    final mouse = MouseTransport(send: (cmd) async { commands.add(cmd); return cmd.endsWith(':up') ? 'input_ok' : 'input_failed'; }, onError: () => errors++);
    mouse.move(2, 3); mouse.click(false);
    await tester.pump(const Duration(milliseconds: 30));
    expect(errors, 1);
    expect(commands.any((s) => s.endsWith(':left')), isFalse);
    expect(commands.last.endsWith(':up'), isTrue);
    mouse.dispose();
    await tester.pump(const Duration(milliseconds: 30));
  });
  test('mouse protocol rejects malformed and oversized movement', () {
    const prefix = 'mouse:0123456789abcdef0123456789abcdef';
    expect(validMouseCommand('$prefix:move:-512:512'), isTrue);
    expect(validMouseCommand('$prefix:wheel:-120'), isTrue);
    for (final bad in ['$prefix:move:513:0', '$prefix:wheel:1201', '$prefix:click:any', 'mouse:bad:down']) {
      expect(validMouseCommand(bad), isFalse);
    }
  });
}
